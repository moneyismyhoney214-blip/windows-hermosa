import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'certificate_pinning.dart';

/// `package:http` client that runs every successful response's leaf
/// cert through [CertificatePinning.checkAccepted]. Drop-in replacement
/// for `IOClient` — same constructor, same surface.
///
/// `package:http` 1.x makes `IOStreamedResponse.inner` private, so we
/// can't grab the cert from a returned response. Instead we re-implement
/// the slice of `IOClient.send()` we need (opens the request via the
/// supplied `HttpClient`, pipes the request stream into it, captures
/// the peer certificate from the raw `HttpClientResponse`, then wraps
/// the response back into an `IOStreamedResponse` for the caller).
///
/// Behaviour matches `IOClient.send` for the paths BaseClient exercises
/// (GET / POST / multipart). It does NOT replicate the abort-token
/// handling from `IOClient` — BaseClient doesn't use it.
class PinningHttpClient extends http.BaseClient {
  PinningHttpClient(this._inner);

  HttpClient? _inner;

  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) async {
    final client = _inner;
    if (client == null) {
      throw http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }

    final stream = request.finalize();

    try {
      final ioRequest = await client.openUrl(request.method, request.url)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = (request.contentLength ?? -1)
        ..persistentConnection = request.persistentConnection;
      request.headers.forEach((name, value) {
        ioRequest.headers.set(name, value);
      });

      final response = await stream.pipe(ioRequest) as HttpClientResponse;

      // *** The pinning step *** — runs once per successful handshake.
      // Throws HandshakeException in enforce mode if the leaf hash
      // isn't in the pin list; the throw propagates out of `send()`
      // exactly like any other transport error.
      final cert = response.certificate;
      if (cert != null) {
        CertificatePinning.checkAccepted(
          cert,
          request.url.host,
          request.url.hasPort ? request.url.port : 443,
        );
      }

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        // Fold multi-value headers the same way IOClient does — last
        // value wins, joined by comma for repeating headers like
        // Set-Cookie. Matches `package:http`'s behaviour.
        headers[name] = values.join(',');
      });

      return IOStreamedResponse(
        response.handleError(
          (Object error) {
            final httpException = error as HttpException;
            throw http.ClientException(httpException.message, httpException.uri);
          },
          test: (error) => error is HttpException,
        ),
        response.statusCode,
        contentLength:
            response.contentLength == -1 ? null : response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        inner: response,
      );
    } on SocketException catch (error) {
      throw http.ClientException(error.message, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, request.url);
    }
  }

  @override
  void close() {
    _inner?.close(force: true);
    _inner = null;
  }
}
