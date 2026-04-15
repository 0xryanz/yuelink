<?php

namespace Plugin\YueOnlineCount;

use App\Models\User;
use App\Services\Plugin\AbstractPlugin;
use Illuminate\Support\Carbon;

/**
 * Inject online_count, device_limit and last_online_at into the
 * user.subscribe.response payload. XBoard's UserController@getSubscribe
 * uses an explicit select() that omits online_count and last_online_at
 * even though the columns exist on v2_user and DeviceStateService keeps
 * them up to date (Redis-backed dedup-by-IP, 600s TTL).
 *
 * Freshness filter: if last_online_at is older than STALE_AFTER_SECONDS
 * the stored online_count is treated as stale and reported as 0.
 * DeviceStateService only writes the column on activity, never zeroes it,
 * so without this filter a user whose devices all disconnected an hour
 * ago would still appear "online".
 *
 * The threshold MUST stay in sync with yuebot's Telegram-bot DAO
 * (DEVICE_ONLINE_STALE_SECONDS at the top of
 * /opt/telegram-bot/yue/dao/v2_user.py on 23.80.91.14) so the bot's
 * "查询在线设备" reply and the YueLink mine page show the same number.
 * Change one without changing the other and the two surfaces will
 * silently disagree.
 */
class Plugin extends AbstractPlugin
{
    private const STALE_AFTER_SECONDS = 600;

    public function boot(): void
    {
        $this->filter('user.subscribe.response', function ($user) {
            $id = request()->user()?->id;
            if (!$id) {
                return $user;
            }
            $row = User::query()
                ->whereKey($id)
                ->select(['online_count', 'last_online_at'])
                ->first();
            if (!$row) {
                return $user;
            }
            $online = (int) ($row->online_count ?? 0);
            $lastSeen = $row->last_online_at;
            $fresh = $lastSeen
                && Carbon::parse($lastSeen)->diffInSeconds(now()) <= self::STALE_AFTER_SECONDS;
            $user['online_count'] = $fresh ? $online : 0;
            if ($lastSeen) {
                $user['last_online_at'] = $lastSeen;
            }
            return $user;
        });
    }
}
