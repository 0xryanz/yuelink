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
 * Freshness filter: if last_online_at is older than 10 minutes the
 * stored online_count is treated as stale and reported as 0. This
 * matches the yuebot Telegram-bot DAO query behaviour (see
 * batch_check_online_device_counts in dao/v2_user.py) so both the bot
 * and the desktop client see the same numbers.
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
