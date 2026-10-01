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
  /// and never as a bare dot: "how many" is what a doctor decides on between
  /// consultations.
  final int badge;

  /// Something is there and a count would mean nothing — an update waiting.
  final bool showDot;
}

/// The doctor's bar, as the design canvas draws it: white, floating over the
/// page, 64 tall with 28 corners, the place you are in lit behind its icon.
///
/// Only the doctor's shell uses it. The patient and dietician apps keep the
/// glass bar they have always had — this is the doctor panel's rebuild, and
/// nobody asked for their screens to move under them.
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
        padding: EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s6),
        child: Container(
          height: D.bar,
          padding: EdgeInsets.all(D.gapTight),
          decoration: BoxDecoration(
            color: D.card,
            borderRadius: BorderRadius.circular(D.rBar),
            border: Border.all(color: D.line),
            boxShadow: D.liftBar,
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(width: D.s1 / 2),
                Expanded(
                  child: _BarItem(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
              ],
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
      child: Material(
        color: active ? D.brandTint : Colors.transparent,
        borderRadius: BorderRadius.circular(D.rBarItem),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(D.rBarItem),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    active ? item.selectedIcon : item.icon,
                    size: D.iconDisc,
                    color: colour,
                  ),
                  if (item.badge > 0)
                    Positioned(
                      top: -D.gapTight,
                      left: D.s3,
                      child: Container(
                        height: D.badgeMin,
                        constraints: const BoxConstraints(minWidth: D.badgeMin),
                        padding: EdgeInsets.symmetric(horizontal: D.s1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: D.brand,
                          borderRadius: D.rPill,
                          border: Border.all(color: D.card, width: 2),
                        ),
                        child: Text(
                          item.badge > 99 ? '99+' : '${item.badge}',
                          textAlign: TextAlign.center,
                          style: D.badgeText.copyWith(color: D.onBrand),
                        ),
                      ),
                    )
                  else if (item.showDot)
                    Positioned(
                      top: -D.s1 / 2,
                      right: -D.s1 / 2,
                      child: Container(
                        width: D.s2,
                        height: D.s2,
                        decoration: BoxDecoration(
                          color: D.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: D.card, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: D.s1 / 2),
              Text(
                item.label,
                style: (active ? D.navLabelOn : D.navLabel).copyWith(color: colour),
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
