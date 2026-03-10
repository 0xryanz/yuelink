import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../services/app_notifier.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// Modern Configuration Management Page
class ConfigurationsPage extends ConsumerWidget {
  const ConfigurationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            expandedHeight: 100.0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.lg),
              title: Text(
                'Profiles',
                style: YLText.display.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 28,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () {
                  AppNotifier.info('Add profile coming soon');
                },
              ),
              const SizedBox(width: YLSpacing.sm),
            ],
          ),
          
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.sm),
            sliver: profilesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CupertinoActivityIndicator()),
              ),
              error: (err, stack) => SliverToBoxAdapter(
                child: Center(child: Text('Error: $err', style: YLText.body.copyWith(color: YLColors.error))),
              ),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return SliverToBoxAdapter(child: _buildEmptyState(context));
                }

                final activeProfile = profiles.where((p) => p.id == activeId).firstOrNull;
                final otherProfiles = profiles.where((p) => p.id != activeId).toList();

                return SliverList(
                  delegate: SliverChildListDelegate([
                    
                    // Quick Import Input (Premium Style)
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
                        borderRadius: BorderRadius.circular(YLRadius.lg),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                          width: 0.5,
                        ),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Paste subscription URL...',
                          hintStyle: YLText.body.copyWith(color: YLColors.zinc500),
                          prefixIcon: const Icon(Icons.link_rounded, size: 20, color: YLColors.zinc400),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: FilledButton(
                              onPressed: () => AppNotifier.info('Import coming soon'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                minimumSize: const Size(0, 32),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.sm)),
                              ),
                              child: const Text('Import'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    if (activeProfile != null) ...[
                      const SizedBox(height: YLSpacing.xxl),
                      Text('ACTIVE PROFILE', style: YLText.caption.copyWith(color: YLColors.zinc500, letterSpacing: 1.2)),
                      const SizedBox(height: YLSpacing.sm),
                      _ProfileCard(
                        id: activeProfile.id,
                        name: activeProfile.name,
                        url: activeProfile.url ?? 'Local File',
                        updatedAt: _formatDate(activeProfile.lastUpdated),
                        isActive: true,
                        isExpired: activeProfile.subInfo?.isExpired ?? false,
                      ),
                    ],
                    
                    if (otherProfiles.isNotEmpty) ...[
                      const SizedBox(height: YLSpacing.xxl),
                      Text('ALL PROFILES', style: YLText.caption.copyWith(color: YLColors.zinc500, letterSpacing: 1.2)),
                      const SizedBox(height: YLSpacing.sm),
                      ...otherProfiles.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: YLSpacing.md),
                        child: _ProfileCard(
                          id: p.id,
                          name: p.name,
                          url: p.url ?? 'Local File',
                          updatedAt: _formatDate(p.lastUpdated),
                          isActive: false,
                          isExpired: p.subInfo?.isExpired ?? false,
                        ),
                      )),
                    ],
                    
                    const SizedBox(height: 100), 
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: YLColors.zinc300),
          const SizedBox(height: YLSpacing.xl),
          Text('No Profiles Found', style: YLText.titleLarge),
          const SizedBox(height: YLSpacing.sm),
          Text(
            'Add a subscription URL or import a local config\nto get started.',
            style: YLText.body.copyWith(color: YLColors.zinc500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  final String id;
  final String name;
  final String url;
  final String updatedAt;
  final bool isActive;
  final bool isExpired;

  const _ProfileCard({
    required this.id,
    required this.name,
    required this.url,
    required this.updatedAt,
    required this.isActive,
    required this.isExpired,
  });

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _isApplying = false;

  void _handleUse() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      AppNotifier.info('Restarting core to apply profile...');
      await ref.read(coreActionsProvider).stop();
      
      final config = await ProfileService.loadConfig(widget.id);
      if (config != null) {
        final ok = await ref.read(coreActionsProvider).start(config);
        if (ok) {
          ref.read(activeProfileIdProvider.notifier).select(widget.id);
          AppNotifier.success('Profile applied: ${widget.name}');
        }
      } else {
        AppNotifier.error('Failed to read config file');
      }
    } else {
      ref.read(activeProfileIdProvider.notifier).select(widget.id);
      AppNotifier.success('Profile selected: ${widget.name}');
    }

    if (mounted) setState(() => _isApplying = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return YLSurface(
      padding: const EdgeInsets.all(YLSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Indicator
              Padding(
                padding: const EdgeInsets.only(top: 6.0, right: 12.0),
                child: YLStatusDot(
                  color: widget.isActive 
                      ? YLColors.connected 
                      : (widget.isExpired ? YLColors.error : YLColors.zinc300),
                  glow: widget.isActive,
                ),
              ),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: YLText.titleMedium.copyWith(
                        color: widget.isExpired ? YLColors.error : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.url,
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Actions Menu
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                color: YLColors.zinc400,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => AppNotifier.info('Menu coming soon'),
              ),
            ],
          ),
          
          const SizedBox(height: YLSpacing.lg),
          const Divider(),
          const SizedBox(height: YLSpacing.lg),
          
          // Footer Stats & Actions
          Row(
            children: [
              Icon(
                widget.isExpired ? Icons.error_outline_rounded : Icons.cloud_sync_rounded, 
                size: 14, 
                color: widget.isExpired ? YLColors.error : YLColors.zinc400
              ),
              const SizedBox(width: 6),
              Text(
                widget.isExpired ? 'Expired' : 'Updated ${widget.updatedAt}',
                style: YLText.caption.copyWith(
                  color: widget.isExpired ? YLColors.error : YLColors.zinc500,
                ),
              ),
              const Spacer(),
              if (!widget.isActive) ...[
                OutlinedButton(
                  onPressed: _isApplying ? null : _handleUse,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YLRadius.sm)),
                  ),
                  child: _isApplying 
                      ? const CupertinoActivityIndicator(radius: 7)
                      : const Text('Use'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
