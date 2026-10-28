/// 保险库操作失败。所有异常只带错误码，不带任何密钥值。
sealed class VaultException implements Exception {
  const VaultException(this.code);

  final String code;

  @override
  String toString() => 'VaultException($code)';
}

class VaultLockedException extends VaultException {
  const VaultLockedException() : super('locked');
}

class VaultFormatException extends VaultException {
  const VaultFormatException([this.detail = '']) : super('format');

  final String detail;

  @override
  String toString() => 'VaultFormatException($detail)';
}

class VaultDecryptException extends VaultException {
  const VaultDecryptException() : super('decrypt');
}

class VaultStorageException extends VaultException {
  const VaultStorageException(super.code);
}
