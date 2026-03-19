import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../core/storage/settings_service.dart';
import '../../theme.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    SettingsService.setHasSeenOnboarding(true);
    widget.onComplete();
  }

  void _next() {
    if (_currentPage < 3) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pages = [
      _OnboardingContent(
        icon: Icons.link_rounded,
        iconColor: isDark ? Colors.white : YLColors.primary,
        title: s.onboardingWelcome,
        description: s.onboardingWelcomeDesc,
      ),
      _OnboardingContent(
        icon: Icons.power_settings_new_rounded,
        iconColor: YLColors.connected,
        title: s.onboardingConnect,
        description: s.onboardingConnectDesc,
      ),
      _OnboardingContent(
        icon: Icons.public_rounded,
        iconColor: Colors.blue,
        title: s.onboardingNodes,
        description: s.onboardingNodesDesc,
      ),
      _OnboardingContent(
        icon: Icons.storefront_rounded,
        iconColor: Colors.orange,
        title: s.onboardingStore,
        description: s.onboardingStoreDesc,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(s.onboardingSkip,
                          style:
                              YLText.body.copyWith(color: YLColors.zinc400)),
                    ),
                  ),
                ),

                // Page content
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: pages,
                  ),
                ),

                // Page indicators
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final isActive = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isDark ? Colors.white : YLColors.primary)
                              : (isDark
                                  ? YLColors.zinc700
                                  : YLColors.zinc200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),

                // Next / Done button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            isDark ? Colors.white : YLColors.primary,
                        foregroundColor:
                            isDark ? YLColors.primary : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YLRadius.xl),
                        ),
                      ),
                      child: Text(
                        _currentPage == 3
                            ? s.onboardingDone
                            : s.onboardingNext,
                        style: YLText.label
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _OnboardingContent({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: iconColor),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            style: YLText.titleLarge.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : YLColors.zinc900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: YLText.body.copyWith(
              color: YLColors.zinc500,
              height: 1.6,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
