import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class SpecPill extends StatelessWidget {
  final String label;
  final String value;
  final bool highlightAmber;

  const SpecPill(this.label, this.value, {super.key, this.highlightAmber = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: highlightAmber ? const Color(0xFFFFFBEB) : AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: highlightAmber
              ? const Color(0xFFFDE68A)
              : AppColors.outlineLight,
        ),
      ),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontSize: 10.5,
            color: highlightAmber
                ? const Color(0xFF92400E)
                : AppColors.textSecondary,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: highlightAmber
                    ? const Color(0xFF78350F)
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


