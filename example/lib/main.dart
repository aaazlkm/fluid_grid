import 'package:fluid_grid/fluid_grid.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Photos — fluid_grid',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0A84FF), brightness: Brightness.light, useMaterial3: true),
    home: const PhotoGalleryPage(),
  );
}

/// A stand-in for a photo: a stable id and a hue used to render a gradient
/// thumbnail, so the example needs no bundled image assets.
class Photo {
  const Photo({required this.id, required this.hue});

  final String id;
  final double hue;
}

/// A dated group of photos, mirroring the Photos app's day sections.
class PhotoSection {
  PhotoSection({required this.id, required this.title, required this.photos});

  final String id;
  final String title;
  List<Photo> photos;
}

class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});

  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  static const _minColumns = 2;
  static const _maxColumns = 6;

  int _columns = 3;
  late final List<PhotoSection> _sections = _seedSections();

  int _nextHue = 0;

  Photo _makePhoto(String id) {
    // Spread hues around the wheel so adjacent thumbnails stay distinct.
    final hue = (_nextHue * 47) % 360;
    _nextHue++;
    return Photo(id: id, hue: hue.toDouble());
  }

  List<PhotoSection> _seedSections() => [
    PhotoSection(id: 'today', title: 'Today', photos: [for (var i = 0; i < 8; i++) _makePhoto('today-$i')]),
    PhotoSection(id: 'yesterday', title: 'Yesterday', photos: [for (var i = 0; i < 17; i++) _makePhoto('yesterday-$i')]),
    PhotoSection(id: 'week', title: 'Last Week', photos: [for (var i = 0; i < 29; i++) _makePhoto('week-$i')]),
    PhotoSection(id: 'month', title: 'Last Month', photos: [for (var i = 0; i < 42; i++) _makePhoto('month-$i')]),
    PhotoSection(id: 'year', title: 'Last Year', photos: [for (var i = 0; i < 60; i++) _makePhoto('year-$i')]),
  ];

  void _onReorderFinished(GridReorderResult<Photo> result) {
    setState(() {
      for (final section in _sections) {
        section.photos = result.itemsOf(section.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Library', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            Text('Pinch to zoom · long-press to move', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '$_columns cols',
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        // The grid sizes itself to its content and does not scroll; the
        // surrounding scrollable is what it uses for autoscroll and focal
        // anchoring during a pinch.
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FluidGrid<Photo>(
            crossAxisCount: _columns,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            idOf: (photo) => photo.id,
            zoomConfig: const GridZoomConfig(minCrossAxisCount: _minColumns, maxCrossAxisCount: _maxColumns),
            onCrossAxisCountChanged: (count) => setState(() => _columns = count),
            onReorderFinished: _onReorderFinished,
            sections: [
              for (final section in _sections)
                GridSection(
                  id: section.id,
                  items: section.photos,
                  header: _SectionHeader(title: section.title, count: section.photos.length),
                ),
            ],
            liftedBuilder: (context, photo, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, spreadRadius: 1)],
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
            ),
            itemBuilder: (context, photo) => _PhotoTile(photo: photo),
          ),
        ],
      ),
    );
  }
}

/// A square, edge-to-edge thumbnail. The AspectRatio makes the height equal the
/// column width, so every masonry cell is a perfect square — the Photos look.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final base = HSLColor.fromAHSL(1, photo.hue, 0.62, 0.55).toColor();
    final light = HSLColor.fromAHSL(1, (photo.hue + 24) % 360, 0.7, 0.68).toColor();
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, base]),
        ),
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(_iconFor(photo.hue), color: Colors.white70, size: 18),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(double hue) {
    const icons = [Icons.landscape, Icons.pets, Icons.local_cafe, Icons.beach_access, Icons.park, Icons.camera_alt];
    return icons[(hue ~/ 47).toInt() % icons.length];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(width: 8),
        Text('$count', style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ],
    ),
  );
}
