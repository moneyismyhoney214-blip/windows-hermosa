import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.operations.AuthorizeOperation
import com.example.flutter_terminal_sdk.common.operations.BaseOperation
import com.example.flutter_terminal_sdk.common.operations.CaptureAuthorizationOperation
import com.example.flutter_terminal_sdk.common.operations.CaptureAuthorizationWithTapOperation
import com.example.flutter_terminal_sdk.common.operations.CheckRequiredPermissionsOperation
import com.example.flutter_terminal_sdk.common.operations.ConnectTerminalOperation
import com.example.flutter_terminal_sdk.common.operations.DismissReaderUiOperation
import com.example.flutter_terminal_sdk.common.operations.GetPendingTotalOperation
import com.example.flutter_terminal_sdk.common.operations.GetReconciliationListOperation
import com.example.flutter_terminal_sdk.common.operations.ToImageOperation
import com.example.flutter_terminal_sdk.common.operations.GetReconciliationOperation
import com.example.flutter_terminal_sdk.common.operations.GetTerminalConfigOperation
import com.example.flutter_terminal_sdk.common.operations.GetTerminalListOperation
import com.example.flutter_terminal_sdk.common.operations.GetTerminalOperation
import com.example.flutter_terminal_sdk.common.operations.GetIntentOperation
import com.example.flutter_terminal_sdk.common.operations.GetIntentListOperation
import com.example.flutter_terminal_sdk.common.operations.GetUserOperation
import com.example.flutter_terminal_sdk.common.operations.GetUsersOperation
import com.example.flutter_terminal_sdk.common.operations.IncrementAuthorizationOperation
import com.example.flutter_terminal_sdk.common.operations.InitializeOperation
import com.example.flutter_terminal_sdk.common.operations.InstallmentsOperation
import com.example.flutter_terminal_sdk.common.operations.IsNfcEnableOperation
import com.example.flutter_terminal_sdk.common.operations.IsTerminalReadyOperation
import com.example.flutter_terminal_sdk.common.operations.IsWifiEnableOperation
import com.example.flutter_terminal_sdk.common.operations.LogoutOperation
import com.example.flutter_terminal_sdk.common.operations.OpenRefundOperation
import com.example.flutter_terminal_sdk.common.operations.PurchaseOperation
import com.example.flutter_terminal_sdk.common.operations.PurchaseVoidOperation
import com.example.flutter_terminal_sdk.common.operations.PurchaseWithTipOperation
import com.example.flutter_terminal_sdk.common.operations.ReconcileOperation
import com.example.flutter_terminal_sdk.common.operations.RefundOperation
import com.example.flutter_terminal_sdk.common.operations.RefundVoidOperation
import com.example.flutter_terminal_sdk.common.operations.ReverseTransactionOperation
import com.example.flutter_terminal_sdk.common.operations.SendEmailOtpOperation
import com.example.flutter_terminal_sdk.common.operations.SendMobileOtpOperation
import com.example.flutter_terminal_sdk.common.operations.TipTransactionOperation
import com.example.flutter_terminal_sdk.common.operations.VerifyEmailOtpOperation
import com.example.flutter_terminal_sdk.common.operations.VerifyJWTOperation
import com.example.flutter_terminal_sdk.common.operations.VerifyMobileOtpOperation
import com.example.flutter_terminal_sdk.common.operations.VoidAuthorizationOperation

class NearpayOperatorFactory(private val provider: NearpayProvider) {
    private val operations: Map<String, BaseOperation> = mapOf(
        "initialize" to InitializeOperation(provider),
        "sendMobileOtp" to SendMobileOtpOperation(provider),
        "sendEmailOtp" to SendEmailOtpOperation(provider),
        "verifyMobileOtp" to VerifyMobileOtpOperation(provider),
        "verifyEmailOtp" to VerifyEmailOtpOperation(provider),
        "purchase" to PurchaseOperation(provider),
        "purchaseVoid" to PurchaseVoidOperation(provider),
        "refund" to RefundOperation(provider),
        "refundVoid" to RefundVoidOperation(provider),
        "getTerminalList" to GetTerminalListOperation(provider),
        "connectTerminal" to ConnectTerminalOperation(provider),
        "getIntent" to GetIntentOperation(provider),
        "getIntentList" to GetIntentListOperation(provider),
        "getReconciliationList" to GetReconciliationListOperation(provider),
        "getReconciliation" to GetReconciliationOperation(provider),
        "reconcile" to ReconcileOperation(provider),
        "getUser" to GetUserOperation(provider),
        "getUsers" to GetUsersOperation(provider),
        "logout" to LogoutOperation(provider),
        "getTerminal" to GetTerminalOperation(provider),
        "jwtVerify" to VerifyJWTOperation(provider),
        "reverseTransaction" to ReverseTransactionOperation(provider),
        "checkRequiredPermissions" to CheckRequiredPermissionsOperation(provider),
        "isWifiEnabled" to IsWifiEnableOperation(provider),
        "isNfcEnabled" to IsNfcEnableOperation(provider),
        "authorize" to AuthorizeOperation(provider),
        "captureAuthorization" to CaptureAuthorizationOperation(provider),
        "voidAuthorization" to VoidAuthorizationOperation(provider),
        "incrementAuthorization" to IncrementAuthorizationOperation(provider), // Assuming incrementalAuthorize is similar to authorize
        "isTerminalReady" to IsTerminalReadyOperation(provider),// Assuming incrementalAuthorize is similar to authorize,
        "getPendingTotal" to GetPendingTotalOperation(provider),
        "getTerminalConfig" to GetTerminalConfigOperation(provider),
        "tipTransaction" to TipTransactionOperation(provider),
        "dismissReaderUi" to DismissReaderUiOperation(provider),
        "toImage" to ToImageOperation(provider),
        "openRefund" to OpenRefundOperation(provider),
        "captureAuthorizationWithTap" to CaptureAuthorizationWithTapOperation(provider),
        "purchaseWithTip" to PurchaseWithTipOperation(provider), // Reusing PurchaseOperation for purchaseWithTip
        "installments" to InstallmentsOperation(provider), // Reusing PurchaseOperation for purchaseWithTip

    )

    fun getOperation(method: String): BaseOperation? {
        return operations[method]
    }
}