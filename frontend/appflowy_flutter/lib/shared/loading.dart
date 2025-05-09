import 'dart:async';

import 'package:flutter/material.dart';

class Loading {
  Loading(this.context);

  BuildContext? loadingContext;
  final BuildContext context;

  bool hasStopped = false;

  void start() => unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            loadingContext = context;

            if (hasStopped) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(loadingContext!).maybePop();
                loadingContext = null;
              });
            }

            return const SimpleDialog(
              elevation: 0.0,
              backgroundColor:
                  Colors.transparent, // can change this to your preferred color
              children: [
                Center(
                  child: CircularProgressIndicator(),
                ),
              ],
            );
          },
        ),
      );

  void stop() {
    if (loadingContext != null) {
      Navigator.of(loadingContext!).pop();
      loadingContext = null;
    }

    hasStopped = true;
  }
}
