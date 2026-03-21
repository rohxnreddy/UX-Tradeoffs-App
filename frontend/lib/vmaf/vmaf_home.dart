import 'package:flutter/material.dart';
import 'vmaf_minimal.dart';
import 'vmaf.dart';

class VmafHome extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const VmafHome({super.key, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Hamburger
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.menu, color: Color(0xFF202124), size: 24),
                onPressed: onMenuPressed,
              ),

              const SizedBox(height: 40),

              // Title
              const Text(
                "VMAF",
                style: TextStyle(
                  color: Color(0xFF202124),
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "VIDEO QUALITY TESTER",
                style: TextStyle(
                  color: Color(0xFF9AA0A6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 48),

              _ModeCard(
                label: "MINIMAL",
                description: "",
                icon: Icons.circle_outlined,
                accentColor: const Color(0xFF0097A7),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VmafMinimal(onMenuPressed: onMenuPressed),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              _ModeCard(
                label: "DEBUG",
                description: "",
                icon: Icons.tune,
                accentColor: const Color(0xFF2E7D32),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VmafPlayer(onMenuPressed: onMenuPressed),
                  ),
                ),
              ),

              const Spacer(),

              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  "Select a mode to begin",
                  style: TextStyle(
                    color: Color(0xFFBDBDBD),
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  final String       label;
  final String       description;
  final IconData     icon;
  final Color        accentColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) => setState(() => _pressed = false),
      onTapCancel: ()  => setState(() => _pressed = false),
      onTap:       widget.onTap,
      child: AnimatedScale(
        scale:    _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.accentColor.withOpacity(0.06)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _pressed
                  ? widget.accentColor.withOpacity(0.4)
                  : const Color(0xFFE0E0E0),
              width: 1.5,
            ),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: widget.accentColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.accentColor.withOpacity(0.2)),
              ),
              child: Icon(widget.icon, color: widget.accentColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),

                  // 👇 Only show if description is not empty
                  if (widget.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: const TextStyle(
                        color: Color(0xFF9AA0A6),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios,
              color: widget.accentColor.withOpacity(0.35),
              size: 13,
            ),
          ]),
        ),
      ),
    );
  }
}