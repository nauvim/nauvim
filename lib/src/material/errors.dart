import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import 'theme.dart';

class NauvimErrorBanner extends StatelessWidget {
  const NauvimErrorBanner({super.key, required this.controller});
  final NauvimController controller;

  @override
  Widget build(BuildContext context) {
    final appearance = NauvimTheme.of(context);
    return Material(
      color: appearance.errorColor,
      child: Padding(
        padding: appearance.errorPadding,
        child: Row(
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.sizeOf(context).height *
                      appearance.errorMaxHeightFraction,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(controller.errors.join('\n')),
                ),
              ),
            ),
            IconButton(
              onPressed: controller.dismissErrors,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}
