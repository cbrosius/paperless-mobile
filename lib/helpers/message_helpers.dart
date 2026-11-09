import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/model/info_message_exception.dart';
import 'package:paperless_mobile/core/translation/error_code_localization_mapper.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class SnackBarActionConfig {
  final String label;
  final VoidCallback onPressed;

  SnackBarActionConfig({required this.label, required this.onPressed});
}

enum SnackbarType { error, info }

void showSnackBar(
  BuildContext context,
  String message, {
  String? details,
  SnackBarActionConfig? action,
  SnackbarType type = SnackbarType.info,
  Duration duration = const Duration(seconds: 5),
}) {
  final color = type == SnackbarType.error
      ? Theme.of(context).colorScheme.errorContainer
      : Theme.of(context).colorScheme.inverseSurface;
  final foregroundColor = type == SnackbarType.error
      ? Theme.of(context).colorScheme.onErrorContainer
      : Theme.of(context).colorScheme.onInverseSurface;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        content: Row(
          children: [
            if (type == SnackbarType.error)
              Icon(
                Icons.error_outline,
                color: foregroundColor,
              ).paddedOnly(right: 8),
            Flexible(
              child: (details != null)
                  ? RichText(
                      maxLines: 5,
                      text: TextSpan(
                        text: message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                        ),
                        children: <TextSpan>[
                          TextSpan(
                            text: "\n$details",
                            style: TextStyle(
                              color: foregroundColor,
                              fontStyle: FontStyle.italic,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(message, style: TextStyle(color: foregroundColor)),
            ),
          ],
        ),
        action: action != null
            ? SnackBarAction(
                label: action.label,
                onPressed: action.onPressed,
                textColor: foregroundColor,
              )
            : null,
        duration: duration,
      ),
    );
}

void showGenericError(
  BuildContext context,
  dynamic error, [
  StackTrace? stackTrace,
]) {
  if (error is DioException && error.error != null) {
    showGenericError(context, error.error, stackTrace ?? error.stackTrace);
    return;
  }

  if (error is PaperlessApiException) {
    showErrorMessage(context, error, stackTrace);
    return;
  }

  if (error is PaperlessFormValidationException) {
    showGenericError(
      context,
      error.validationMessages.entries
          .map((e) => "${e.key}: ${e.value}")
          .join("\n"),
      stackTrace,
    );
    return;
  }
  if (error is PaperlessUnauthorizedException) {
    final message = (error.message != null && error.message!.trim().isNotEmpty)
        ? error.message!
        : S.of(context)!.unauthorizedErrorMessage;
    showLocalizedError(
      context,
      message,
      stackTrace,
    );
    return;
  }
  if (error is InfoMessageException) {
    showInfoMessage(context, error, stackTrace);
    return;
  }
  showSnackBar(context, error.toString(), type: SnackbarType.error);
  log(
    "An error has occurred.",
    error: error,
    stackTrace: stackTrace,
    time: DateTime.now(),
  );
}

void showLocalizedError(
  BuildContext context,
  String localizedMessage, [
  StackTrace? stackTrace,
]) {
  showSnackBar(context, localizedMessage, type: SnackbarType.error);
  log(localizedMessage, stackTrace: stackTrace);
}

void showErrorMessage(
  BuildContext context,
  PaperlessApiException error, [
  StackTrace? stackTrace,
]) {
  showSnackBar(
    context,
    translateError(context, error.code),
    details: error.details,
    type: SnackbarType.error,
  );
  log(
    "An error has occurred.",
    error: error,
    stackTrace: stackTrace,
    time: DateTime.now(),
  );
}

void showInfoMessage(
  BuildContext context,
  InfoMessageException error, [
  StackTrace? stackTrace,
]) {
  showSnackBar(
    context,
    translateError(context, error.code),
    details: error.message,
  );
}
