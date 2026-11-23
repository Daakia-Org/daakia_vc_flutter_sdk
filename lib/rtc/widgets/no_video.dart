import 'package:daakia_vc_flutter_sdk/presentation/widgets/initials_circle.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:flutter/material.dart';


class NoVideoWidget extends StatelessWidget {
  const NoVideoWidget({this.name, this.userAvatar, this.isSpeaker = false, super.key});

  final String? name;
  final String? userAvatar;
  final bool isSpeaker;

  @override
  Widget build(BuildContext context) {
    final initials = Utils.getInitials(name);
    final bgColor = Utils.generateUniqueColorFromInitials(name ?? "U");

    final bool hasAvatar =
        userAvatar != null && userAvatar!.trim().isNotEmpty;

    return Container(
      alignment: Alignment.center,
      child: hasAvatar
          ? ClipOval(
        child: Image.network(
          userAvatar!,
          fit: BoxFit.cover,
          width: getSize(isSpeaker),
          height: getSize(isSpeaker),
          // Initials until the picture has downloaded, then a quick fade,
          // so the circle is never empty.
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : _buildInitials(initials, bgColor),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              wasSynchronouslyLoaded
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: child,
                    ),
          errorBuilder: (_, __, ___) => _buildInitials(initials, bgColor),
        ),
      )
          : _buildInitials(initials, bgColor),
    );
  }

  Widget _buildInitials(String initials, Color bgColor) {
    return InitialsCircle(
      initials: initials,
      backgroundColor: bgColor,
      size: getSize(isSpeaker),
      textStyle: getTextStyle(isSpeaker),
    );
  }
  
  double getSize(bool isSpeaker) {
    return isSpeaker ? 90 : 50;
  }

  TextStyle getTextStyle(bool isSpeaker) {
    return TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: isSpeaker ? 25.0 : 15.0,
    );
  }
}

