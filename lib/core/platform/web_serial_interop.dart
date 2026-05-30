// Web Serial API bindings via dart:js_interop.
//
// Self-contained external declarations for the subset of the Web Serial API
// Helios uses, so we don't depend on a particular package:web version
// exposing them. Only meaningful when compiled for the web; on other targets
// these symbols are analysed but never invoked.
//
// Spec: https://wicg.github.io/serial/
@JS()
library;

import 'dart:js_interop';

/// `navigator.serial` — may be undefined on unsupported browsers.
@JS('navigator.serial')
external Serial? get serial;

/// The Web Serial entry point.
extension type Serial._(JSObject _) implements JSObject {
  /// Ports the user has already granted this origin access to.
  external JSPromise<JSArray<WebSerialPort>> getPorts();

  /// Prompt the user to pick a port. MUST be called from a user gesture.
  external JSPromise<WebSerialPort> requestPort();
}

/// A single serial port handle.
extension type WebSerialPort._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(WebSerialOptions options);
  external JSPromise<JSAny?> close();
  external ReadableStream? get readable;
  external WritableStream? get writable;
  external WebSerialPortInfo getInfo();
}

/// USB identity for a granted port (fields are optional / may be undefined).
extension type WebSerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

/// Options passed to `SerialPort.open`.
extension type WebSerialOptions._(JSObject _) implements JSObject {
  external factory WebSerialOptions({
    required int baudRate,
    int dataBits,
    int stopBits,
    String parity,
    int bufferSize,
    String flowControl,
  });
}

extension type ReadableStream._(JSObject _) implements JSObject {
  external ReadableStreamDefaultReader getReader();
}

extension type ReadableStreamDefaultReader._(JSObject _) implements JSObject {
  external JSPromise<ReadableStreamReadResult> read();
  external JSPromise<JSAny?> cancel();
  external void releaseLock();
}

extension type ReadableStreamReadResult._(JSObject _) implements JSObject {
  /// A `Uint8Array` chunk (undefined when [done] is true).
  external JSAny? get value;
  external bool get done;
}

extension type WritableStream._(JSObject _) implements JSObject {
  external WritableStreamDefaultWriter getWriter();
}

extension type WritableStreamDefaultWriter._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny chunk);
  external void releaseLock();
}
