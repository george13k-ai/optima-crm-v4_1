import 'package:crm/app/app.dart';
import 'package:crm/data/mock_backend.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mock = await MockBackend.create();
  runApp(CrmApp(mock: mock));
}
