/// Stable message codes for [EditorCubit] snackbars and panel errors (resolved via l10n).
abstract final class EditorMessage {
  static const binaryFile = 'editor_binary_file';
  static const fileNotFound = 'editor_error_not_found';
  static const fileTooLarge = 'editor_error_too_large';
  static const couldNotRead = 'editor_error_read_failed';
  static const readOnly = 'editor_read_only';

  static const saveFailedPrefix = 'editor_save_failed:';

  static String saveFailed(Object error) => '$saveFailedPrefix$error';
}
