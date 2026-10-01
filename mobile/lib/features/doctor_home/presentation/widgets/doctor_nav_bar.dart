import 'package:flutter/material.dart';

import '../../../../core/theme/doctor_tokens.dart';

/// One place in the doctor's bar.
@immutable
class DoctorNavItem {
  const DoctorNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
    this.showDot = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// A number worth acting on — unread patient messages. Drawn when above zero
  /// and never as a bare dot, because "how many" is the thing a doctor decides
  /// on between consultations.
  final int badge;

  /// Something is there, and the count would be meaningless — an update
  /// waiting to be installed.
  final bool showDot;
}

/// The doctor's bar in the new design: a white bar that floats over the page,
/// the place you are in lit behind its icon.
///
/// Only the doctor's shell uses it. The patient app keeps the glass bar it has
/// always had — this is the doctor panel's rebuild, and nobody asked for their
/// screens to move under them.
class DoctorNavBar extends StatelessWidget {
  const DoctorNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<DoctorNavItem> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s3),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s2),
          decoration: BoxDecoration(
            color: D.card,
            borderRadius: BorderRadius.circular(D.rBar),
            border: Border.all(color: D.line),
            boxShadow: D.liftBar,
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BarItem(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.item, required this.active, required this.onTap});

  final DoctorNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = active ? D.brand : D.inkMuted;

    return Semantics(
      button: true,
      selected: active,
      label: item.badge > 0 ? '${item.label}, ${item.badge} unread' : item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(D.rInner),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: D.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s1),
                decoration: BoxDecoration(
                  color: active ? D.brandTint : null,
                  borderRadius: D.rPill,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(active ? item.selectedIcon : item.icon, color: colour),
                    if (item.badge > 0)
                      Positioned(
                        top: -D.s2,
                        right: -D.s3,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: D.s1),
                          constraints: const BoxConstraints(minWidth: D.s4),
                          decoration: const BoxDecoration(color: D.badge, borderRadius: D.rPill),
                          child: Text(
                            item.badge > 99 ? '99+' : '${item.badge}',
                            textAlign: TextAlign.center,
                            style: D.label.copyWith(color: D.onBrand),
                          ),
                        ),
                      )
                    else if (item.showDot)
                      Positioned(
                        top: -D.s1,
                        right: -D.s1,
                        child: Container(
                          width: D.s2,
                          height: D.s2,
                          decoration: const BoxDecoration(color: D.badge, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: D.s1),
              Text(
                item.label,
                style: D.label.copyWith(color: colour),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
