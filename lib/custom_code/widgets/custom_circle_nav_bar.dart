// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_util.dart';
// Imports other custom widgets
// Imports custom actions
// Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:circle_nav_bar/circle_nav_bar.dart';

class CustomCircleNavBar extends StatefulWidget {
  const CustomCircleNavBar({
    super.key,
    this.width,
    this.height,
    required this.backgroundColor,
    required this.activeColor,
    required this.inactiveColor,
    required this.currentIndex,
  });

  final double? width;
  final double? height;
  final Color backgroundColor;
  final Color activeColor;
  final Color inactiveColor;
  final int currentIndex;

  @override
  State<CustomCircleNavBar> createState() => _CustomCircleNavBarState();
}

class _CustomCircleNavBarState extends State<CustomCircleNavBar> {
  void _navigateToPage(BuildContext context, int index) {
    switch (index) {
      case 0:
        GoRouter.of(context).go('/homePage');
        break;
      case 1:
        GoRouter.of(context).go('/searchPage');
        break;
      case 2:
        GoRouter.of(context).go('/profilePage');
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleNavBar(
      activeIcons: const [
        Icon(Icons.home, color: Colors.white),
        Icon(Icons.search, color: Colors.white),
        Icon(Icons.person, color: Colors.white),
      ],
      inactiveIcons: const [
        Icon(Icons.home_outlined),
        Icon(Icons.search_outlined),
        Icon(Icons.person_outline),
      ],
      color: widget.backgroundColor,
      circleColor: widget.activeColor,
      height: 60,
      circleWidth: 60,
      activeIndex: widget.currentIndex,
      onTap: (index) {
        _navigateToPage(context, index);
      },
    );
  }
}
