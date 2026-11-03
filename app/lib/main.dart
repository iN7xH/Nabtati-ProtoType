// main.dart - app entry point.
//
// Flutter basics:
// - Everything on screen is a "widget" (like a UI component in React).
// - StatelessWidget = no changing data. StatefulWidget = has data that changes.
// - build() returns the widget tree that describes the screen.
// - In a StatefulWidget, call setState(() { ... }) after changing data
//   so Flutter re-runs build() and redraws the screen (like setState in React).

import 'dart:io'; // File class, to show the picked image from the phone's storage

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

/// Below this confidence we tell the user we're not sure (CLAUDE.md: 0.70).
const double lowConfidenceThreshold = 0.70;

void main() {
  runApp(const PlantDoctorApp()); // start the app with our root widget
}

class PlantDoctorApp extends StatelessWidget {
  const PlantDoctorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant Doctor',
      debugShowCheckedModeBanner: false, // hide the red "DEBUG" ribbon
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

/// The only screen of the prototype.
/// It is Stateful because the picked image changes while the app runs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// The "_" prefix makes a class/variable private to this file (Dart has no `private` keyword).
class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  // The currently selected image. `File?` means it can be null (nothing picked yet).
  File? _image;

  bool _loading = false; // true while waiting for the API
  Prediction? _result; // last result from the API (null = none yet)
  String? _error; // error message to show (null = no error)

  /// Opens the gallery or camera and stores the chosen image.
  /// `async` / `await` work like in JavaScript: wait for the user without freezing the UI.
  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024, // shrink big photos -> faster upload later (model uses 224x224 anyway)
      imageQuality: 85, // JPEG quality 0-100
    );

    if (picked == null) return; // user pressed back without choosing

    setState(() {
      _image = File(picked.path);
      _result = null; // new image -> old result no longer applies
      _error = null;
    });
  }

  /// Sends the image to the API and stores the result (or the error).
  Future<void> _diagnose() async {
    if (_image == null) return;

    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });

    try {
      final prediction = await ApiService.predict(_image!);
      if (!mounted) return; // screen was closed while waiting
      setState(() => _result = prediction);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message); // already a friendly message
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
      debugPrint('Unexpected error: $e'); // shows in the `flutter run` terminal
    } finally {
      if (mounted) setState(() => _loading = false); // always stop the spinner
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Scaffold = basic page layout: app bar on top, body below.
      appBar: AppBar(title: const Text('Plant Doctor')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            // stretch = children take the full width
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Expanded = take all the remaining vertical space.
              Expanded(child: _buildImagePreview()),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Diagnose button: disabled (onPressed: null) until an image is picked or while loading.
              FilledButton.icon(
                onPressed: (_image == null || _loading) ? null : _diagnose,
                icon: const Icon(Icons.search),
                label: const Text('Diagnose'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              _buildResultArea(),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom area: spinner, error, result card, or nothing.
  Widget _buildResultArea() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
              ),
            ],
          ),
        ),
      );
    }
    if (_result != null) {
      return _buildResultCard(_result!);
    }
    return const SizedBox.shrink(); // empty widget
  }

  Widget _buildResultCard(Prediction r) {
    final percent = (r.confidence * 100).toStringAsFixed(0);
    final unsure = r.confidence < lowConfidenceThreshold;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Crop: ${_pretty(r.crop)}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              r.isHealthy ? 'Healthy' : 'Disease: ${_pretty(r.disease)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: r.isHealthy ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text('Confidence: $percent%', style: const TextStyle(fontSize: 16)),
            if (unsure) ...[
              // `if` inside a list = only add these widgets when unsure is true.
              const SizedBox(height: 8),
              const Text(
                'Not sure, try a clearer photo of one leaf',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "late_blight" -> "Late blight"
  String _pretty(String s) {
    final text = s.replaceAll('_', ' ').trim();
    if (text.isEmpty) return s;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// Shows the picked image, or a placeholder box if nothing is picked yet.
  Widget _buildImagePreview() {
    if (_image == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green.shade200, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco, size: 72, color: Colors.green),
            SizedBox(height: 12),
            Text('Pick a photo of one leaf', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    // ClipRRect = round the corners of its child (the image).
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(_image!, fit: BoxFit.contain), // `!` = "I know it's not null here"
    );
  }
}
