class SettingsScreenState {
  const SettingsScreenState({
    this.isExporting = false,
    this.isImporting = false,
    this.errorMessage,
    this.successMessage,
  });

  final bool isExporting;
  final bool isImporting;
  final String? errorMessage;
  final String? successMessage;

  SettingsScreenState copyWith({
    bool? isExporting,
    bool? isImporting,
    String? errorMessage,
    String? successMessage,
    bool clearErrorMessage = false,
    bool clearSuccessMessage = false,
  }) {
    return SettingsScreenState(
      isExporting: isExporting ?? this.isExporting,
      isImporting: isImporting ?? this.isImporting,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearSuccessMessage ? null : (successMessage ?? this.successMessage),
    );
  }
}
