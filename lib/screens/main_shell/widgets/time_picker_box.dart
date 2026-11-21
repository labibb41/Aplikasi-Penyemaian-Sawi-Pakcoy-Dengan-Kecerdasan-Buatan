import 'package:flutter/material.dart';

class TimePickerBox extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color border;
  final Color fg;
  final VoidCallback onTap;

  const TimePickerBox({
    super.key,
    required this.label,
    required this.value,
    required this.bg,
    required this.border,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: fg,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                Icon(Icons.schedule_rounded, size: 17, color: fg),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
