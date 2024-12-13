import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart'; // Importa jwt_decoder
import 'dart:convert'; // Para formatear el JSON

class LoggedInScreen extends StatefulWidget {
  @override
  _LoggedInScreenState createState() => _LoggedInScreenState();
}

class _LoggedInScreenState extends State<LoggedInScreen> {
  final _storage = FlutterSecureStorage();
  String? _formattedToken;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccessToken();
  }

  Future<void> _loadAccessToken() async {
    try {
      // Recuperar el token almacenado
      final token = await _storage.read(key: 'access_token');
      print('Token recuperado: $token');

      if (token != null) {
        try {
          // Decodificar el token usando jwt_decoder
          final decoded = JwtDecoder.decode(token);

          // Formatear el contenido del token como JSON legible
          final formatted = JsonEncoder.withIndent('  ').convert(decoded);

          setState(() {
            _formattedToken = formatted;
            _isLoading = false;
          });
        } catch (e) {
          print('Error al decodificar el token JWT: $e');
          setState(() {
            _formattedToken = 'Error al decodificar el token JWT.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _formattedToken = 'No se encontró el token almacenado.';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error al recuperar el token: $e');
      setState(() {
        _formattedToken = 'Error al recuperar el token.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Token Decodificado'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: _isLoading
              ? CircularProgressIndicator() // Mostrar un indicador de carga mientras se obtiene el token
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contenido del Token Decodificado:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    SelectableText(
                      _formattedToken ?? 'Error al decodificar el token.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.left,
                      showCursor: true,
                      cursorColor: Colors.green,
                      cursorWidth: 2.0,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}