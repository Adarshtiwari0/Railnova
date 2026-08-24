import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/skin_tokens.dart';
import '../../providers/theme_provider.dart';

class RailNovaTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;

  const RailNovaTextField({
    super.key,
    this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      style: TextStyle(fontFamily: skin.fontFamily, color: skin.text),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: skin.dim),

        prefixIcon: Icon(prefixIcon, color: skin.primary),

        filled: true,
        fillColor: skin.card,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: skin.border),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: skin.primary, width: 2),
        ),
      ),
    );
  }
}
