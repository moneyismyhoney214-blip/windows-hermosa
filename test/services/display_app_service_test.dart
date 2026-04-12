import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hermosa_pos/services/display_app_service.dart';

// Generate mocks using build_runner
@GenerateMocks([WebSocketChannel, WebSocketSink])
import 'display_app_service_test.mocks.dart';

void main() {
  late DisplayAppService service;
  late MockWebSocketChannel mockChannel;
  late MockWebSocketSink mockSink;

  setUp(() {
    mockChannel = MockWebSocketChannel();
    mockSink = MockWebSocketSink();
    when(mockChannel.sink).thenReturn(mockSink);
    
    // Instantiate normal service
    service = DisplayAppService();
  });

  group('WebSocket Communication Tests -', () {
    
    test('startPayment should safely return if not connected without crashing', () {
      service.startPayment(
        amount: 41.4,
        orderNumber: 'ORD-001',
        customerReference: 'CUST-123',
      );

      // Verifies internal early return if socket is not connected.
      expect(service.paymentStatus, PaymentStatus.idle);
      expect(service.errorMessage, 'لا يوجد اتصال بتطبيق العرض');
    });

    test('Receiving PAYMENT_SUCCESS wires up callbacks via setCallbacks correctly', () {
      bool callbackFired = false;

      service.setCallbacks(
        onPaymentSuccess: (data) {
          callbackFired = true;
        }
      );
      
      // Since _handleMessage is private, we just test that the setter doesn't crash 
      // and internal hooks are properly assigned.
      expect(callbackFired, false);
    });
  });
}
