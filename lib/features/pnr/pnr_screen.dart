import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/skin_tokens.dart';
import '../../providers/theme_provider.dart';

/// PNR lookup isn't something RailNova/RailRadar's free tier provides (see
/// README), so instead of faking a result, this screen hands the PNR off to
/// a public PNR-status checker: the PNR is copied to the clipboard and a
/// browser tab opens straight to that PNR's result page (the PNR is baked
/// into the URL), so the user only has to tap the site's own Search/Check
/// button — or paste if that particular site doesn't read the URL itself.
class PnrScreen extends StatefulWidget {
  const PnrScreen({super.key});

  @override
  State<PnrScreen> createState() => _PnrScreenState();
}

class _PnrScreenState extends State<PnrScreen> {
  final TextEditingController pnrController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isOpening = false;

  String? _validatePnr(String? value) {
    final pnr = value?.trim() ?? "";

    if (pnr.isEmpty) return "Please enter your PNR number";
    if (!RegExp(r'^\d{10}$').hasMatch(pnr)) {
      return "PNR must be exactly 10 digits";
    }

    return null;
  }

  Future<void> _checkPnr() async {
    if (!_formKey.currentState!.validate()) return;

    final pnr = pnrController.text.trim();

    setState(() => _isOpening = true);

    // Copied as a fallback — if the target site's box doesn't read the PNR
    // from the URL, the user can just paste instead of retyping it.
    await Clipboard.setData(ClipboardData(text: pnr));

    final url = Uri.parse("https://www.confirmtkt.com/pnr-status/$pnr");

    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);

      if (!mounted) return;

      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the browser")),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the browser — PNR copied, paste it manually"),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _isOpening = false);
  }

  @override
  void dispose() {
    pnrController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      appBar: skin.appBar("PNR Status"),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: skin.cardDecoration(radius: 16),
                child: TextFormField(
                  controller: pnrController,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  validator: _validatePnr,
                  style: TextStyle(color: skin.text, fontFamily: skin.fontFamily),
                  decoration: InputDecoration(
                    labelText: "Enter 10 Digit PNR",
                    labelStyle: TextStyle(color: skin.dim),
                    prefixIcon: Icon(Icons.confirmation_number, color: skin.primary),
                    counterStyle: TextStyle(color: skin.dim),
                    border: InputBorder.none,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                "Opens your PNR's status on a railway enquiry site — the "
                "number is filled in for you, just tap Search/Check there.",
                style: TextStyle(color: skin.dim, fontSize: 13),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  style: skin.primaryButtonStyle,
                  onPressed: _isOpening ? null : _checkPnr,
                  icon: _isOpening
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.open_in_new),
                  label: const Text("Check PNR", style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
