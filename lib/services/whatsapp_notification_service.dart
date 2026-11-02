import 'package:flutter/material.dart';
import 'whatsapp_service.dart';

/// Legacy service wrapper delegating directly to [WhatsAppService].
@Deprecated('Use WhatsAppService directly.')
class WhatsAppNotificationService {
  static final WhatsAppNotificationService instance = WhatsAppNotificationService._internal();
  WhatsAppNotificationService._internal();

  /// Formats and launches WhatsApp Web / App deep-link to send a digital invoice
  Future<bool> sendDigitalInvoice({
    required String phoneNumber,
    required String customerName,
    required String invoiceNo,
    required double netAmount,
    required String pharmacyName,
    BuildContext? context,
  }) async {
    if (context != null) {
      return await WhatsAppService.sendDigitalInvoice(
        context: context,
        phoneNumber: phoneNumber,
        customerName: customerName,
        invoiceNo: invoiceNo,
        netAmount: netAmount,
        pharmacyName: pharmacyName,
      );
    }
    final phone = WhatsAppService.sanitizePhoneNumber(phoneNumber);
    if (phone.isEmpty) return false;
    final text = "Dear *$customerName*,\n\nThank you for visiting *$pharmacyName*!\nYour Invoice #*$invoiceNo* is ready.\n\n*Total Amount*: Rs. ${netAmount.toStringAsFixed(2)}\n\nGet well soon!";
    return await WhatsAppService.sendCustomMessage(context: context!, phone: phone, text: text);
  }

  /// Sends a chronic medication refill reminder via WhatsApp
  Future<bool> sendRefillReminder({
    required String phoneNumber,
    required String customerName,
    required String medicineName,
    required String pharmacyName,
    BuildContext? context,
  }) async {
    if (context != null) {
      return await WhatsAppService.sendRefillReminder(
        context: context,
        phoneNumber: phoneNumber,
        customerName: customerName,
        medicineName: medicineName,
        pharmacyName: pharmacyName,
      );
    }
    final phone = WhatsAppService.sanitizePhoneNumber(phoneNumber);
    if (phone.isEmpty) return false;
    final text = "Hello *$customerName*,\n\nThis is a friendly reminder from *$pharmacyName*.\nYour supply for *$medicineName* may be running low.\n\nReply to this message or visit us to arrange your timely refill!";
    return await WhatsAppService.sendCustomMessage(context: context!, phone: phone, text: text);
  }
}
