import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imaging;

/// A real, manual on-device crop. No upload, OCR service, or cloud dependency.
class DocumentCrop extends StatefulWidget {
  const DocumentCrop({super.key, required this.bytes, this.privacyGuard});
  final Uint8List bytes;
  final Widget Function(BuildContext context, Widget child)? privacyGuard;
  @override
  State<DocumentCrop> createState() => _DocumentCropState();
}

class _DocumentCropState extends State<DocumentCrop> {
  Rect _crop = const Rect.fromLTRB(.04, .04, .96, .96);
  double _aspect = .75;
  bool _ready = false, _busy = false;
  Uint8List? _normalized;
  String? _error;
  @override
  void initState() {
    super.initState();
    _inspect();
  }

  Future<void> _inspect() async {
    try {
      final prepared = await compute(_prepareImage, widget.bytes);
      if (!mounted) return;
      setState(() {
        if (prepared == null) {
          _error =
              'This image could not be decoded. Choose a JPG or PNG file instead.';
        } else {
          _normalized = prepared.$1;
          _aspect = prepared.$2;
          _ready = true;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final output = await compute(_cropImage, (
        _normalized!,
        _crop.left,
        _crop.top,
        _crop.right,
        _crop.bottom,
      ));
      if (output == null) {
        throw const FormatException('This image could not be cropped.');
      }
      if (mounted) Navigator.pop(context, output);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _move(int corner, Offset delta, Size size) {
    final x = delta.dx / size.width, y = delta.dy / size.height;
    setState(() {
      switch (corner) {
        case 0:
          _crop = Rect.fromLTRB(
            (_crop.left + x).clamp(0, _crop.right - .1).toDouble(),
            (_crop.top + y).clamp(0, _crop.bottom - .1).toDouble(),
            _crop.right,
            _crop.bottom,
          );
        case 1:
          _crop = Rect.fromLTRB(
            _crop.left,
            (_crop.top + y).clamp(0, _crop.bottom - .1).toDouble(),
            (_crop.right + x).clamp(_crop.left + .1, 1).toDouble(),
            _crop.bottom,
          );
        case 2:
          _crop = Rect.fromLTRB(
            _crop.left,
            _crop.top,
            (_crop.right + x).clamp(_crop.left + .1, 1).toDouble(),
            (_crop.bottom + y).clamp(_crop.top + .1, 1).toDouble(),
          );
        case 3:
          _crop = Rect.fromLTRB(
            (_crop.left + x).clamp(0, _crop.right - .1).toDouble(),
            _crop.top,
            _crop.right,
            (_crop.bottom + y).clamp(_crop.top + .1, 1).toDouble(),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      appBar: AppBar(
        title: const Text('Crop document'),
        actions: [
          TextButton(
            onPressed: !_ready || _busy
                ? null
                : () => setState(() => _crop = const Rect.fromLTRB(0, 0, 1, 1)),
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Drag the four corners to frame your document. This scan stays on your device.',
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: Center(
                child: _ready
                    ? AspectRatio(
                        aspectRatio: _aspect,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.biggest;
                            final corners = [
                              Offset(_crop.left, _crop.top),
                              Offset(_crop.right, _crop.top),
                              Offset(_crop.right, _crop.bottom),
                              Offset(_crop.left, _crop.bottom),
                            ];
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: Image.memory(
                                    _normalized!,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _CropOverlay(_crop),
                                  ),
                                ),
                                for (var i = 0; i < corners.length; i++)
                                  Positioned(
                                    left: corners[i].dx * size.width - 24,
                                    top: corners[i].dy * size.height - 24,
                                    child: Semantics(
                                      label: 'Crop corner ${i + 1}',
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanUpdate: (event) =>
                                            _move(i, event.delta, size),
                                        child: SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Center(
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      )
                    : _error != null
                    ? const Icon(Icons.broken_image_outlined, size: 64)
                    : const CircularProgressIndicator(),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !_ready || _busy ? null : _save,
                icon: const Icon(Icons.crop),
                label: Text(_busy ? 'Cropping…' : 'Use cropped scan'),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.privacyGuard?.call(context, screen) ?? screen;
  }
}

class _CropOverlay extends CustomPainter {
  const _CropOverlay(this.crop);
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropOverlay oldDelegate) => oldDelegate.crop != crop;
}

(Uint8List, double)? _prepareImage(Uint8List bytes) {
  // Inspect dimensions before pixel allocation. Only one frame is decoded.
  final decoder = imaging.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) return null;
  if (info.width < 1 ||
      info.height < 1 ||
      info.width > 6000 ||
      info.height > 6000 ||
      info.width * info.height > 16000000) {
    throw const FormatException('Use a scan no larger than 16 megapixels.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) return null;
  final image = imaging.bakeOrientation(decoded);
  // Both preview and crop consume these same orientation-normalized pixels.
  return (
    Uint8List.fromList(imaging.encodeJpg(image, quality: 100)),
    image.width / image.height,
  );
}

Uint8List? _cropImage((Uint8List, double, double, double, double) input) {
  final decoded = imaging.decodeImage(input.$1);
  if (decoded == null) return null;
  final image = imaging.bakeOrientation(decoded);
  final x = (image.width * input.$2).round().clamp(0, image.width - 1).toInt();
  final y = (image.height * input.$3)
      .round()
      .clamp(0, image.height - 1)
      .toInt();
  final width = ((input.$4 - input.$2) * image.width)
      .round()
      .clamp(1, image.width - x)
      .toInt();
  final height = ((input.$5 - input.$3) * image.height)
      .round()
      .clamp(1, image.height - y)
      .toInt();
  final cropped = imaging.copyCrop(
    image,
    x: x,
    y: y,
    width: width,
    height: height,
  );
  return Uint8List.fromList(imaging.encodeJpg(cropped, quality: 94));
}
