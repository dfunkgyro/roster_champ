import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SafeTextField extends StatefulWidget {
  const SafeTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.enabled,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.onTap,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textAlign = TextAlign.start,
    this.expands = false,
    this.maxLength,
    this.autocorrect,
    this.enableSuggestions,
    this.enableIMEPersonalizedLearning,
    this.smartDashesType,
    this.smartQuotesType,
    this.validator,
    this.autovalidateMode,
    this.onSaved,
    this.initialValue,
    this.cursorColor,
    this.cursorWidth,
    this.showCursor,
    this.autofocus = false,
    this.debounceDuration = const Duration(milliseconds: 250),
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool? enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;
  final int? minLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool expands;
  final int? maxLength;
  final bool? autocorrect;
  final bool? enableSuggestions;
  final bool? enableIMEPersonalizedLearning;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final FormFieldSetter<String>? onSaved;
  final String? initialValue;
  final Color? cursorColor;
  final double? cursorWidth;
  final bool? showCursor;
  final bool autofocus;
  final Duration? debounceDuration;

  @override
  State<SafeTextField> createState() => _SafeTextFieldState();
}

class _SafeTextFieldState extends State<SafeTextField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _handleChanged(String value) {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    final delay = widget.debounceDuration;
    if (delay == null || delay == Duration.zero) {
      onChanged(value);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final multiLine = (widget.maxLines != null && widget.maxLines != 1) ||
        widget.expands ||
        (widget.minLines != null && widget.minLines! > 1);
    final effectiveKeyboardType = widget.keyboardType ??
        (multiLine ? TextInputType.multiline : TextInputType.text);
    final effectiveTextInputAction = widget.textInputAction ??
        (multiLine ? TextInputAction.newline : TextInputAction.done);
    final effectiveInputFormatters = widget.inputFormatters;
    final effectiveAutofill =
        (widget.autofillHints != null && widget.autofillHints!.isNotEmpty)
            ? widget.autofillHints
            : null;
    return TextFormField(
      controller: widget.controller,
      initialValue: widget.controller == null ? widget.initialValue : null,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      keyboardType: effectiveKeyboardType,
      textInputAction: effectiveTextInputAction,
      autofillHints: effectiveAutofill,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      onChanged: (value) {
        try {
          _handleChanged(value);
        } catch (_) {}
      },
      onFieldSubmitted: (value) {
        try {
          widget.onSubmitted?.call(value);
        } catch (_) {}
      },
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      inputFormatters: effectiveInputFormatters,
      textCapitalization: widget.textCapitalization,
      style: widget.style,
      textAlign: widget.textAlign,
      expands: widget.expands,
      maxLength: widget.maxLength,
      autocorrect: widget.autocorrect ?? !isAndroid,
      enableSuggestions: widget.enableSuggestions ?? !isAndroid,
      enableIMEPersonalizedLearning:
          widget.enableIMEPersonalizedLearning ?? !isAndroid,
      smartDashesType:
          widget.smartDashesType ?? SmartDashesType.disabled,
      smartQuotesType:
          widget.smartQuotesType ?? SmartQuotesType.disabled,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      onSaved: widget.onSaved,
      cursorColor: widget.cursorColor,
      cursorWidth: widget.cursorWidth ?? 2.0,
      showCursor: widget.showCursor,
      autofocus: widget.autofocus,
    );
  }
}
