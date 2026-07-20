import 'package:fluid_grid/fluid_grid.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The Device photos page shows a dense grid of real thumbnails, and the
  // photos-style pinch builds both endpoint grids at once. Flutter's default
  // 100 MiB image cache is too small for that working set, so it evicts and
  // re-decodes mid-zoom — the grid flashes blank. Give it room to stay
  // resident. (The byte limit binds first; the count is raised for large
  // libraries.)
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes =
        256 <<
        20 // 256 MiB
    ..maximumSize = 4000;
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Photos — fluid_grid',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF0A84FF),
      brightness: Brightness.light,
      useMaterial3: true,
    ),
    home: const PhotoGalleryPage(),
  );
}

/// A stand-in for a photo: a stable id, a running index shown on the tile, and
/// a hue used to render a gradient thumbnail, so the example needs no bundled
/// image assets.
class Photo {
  const Photo({required this.id, required this.index, required this.hue});

  final String id;
  final int index;
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
  static const _zoomLevels = [1, 3, 5, 7, 9, 11, 13, 15];

  int _columns = 3;
  GridZoomStyle _zoomStyle = GridZoomStyle.morph;
  late final List<PhotoSection> _sections = _seedSections();

  int _nextHue = 0;

  Photo _makePhoto(String id) {
    // Spread hues around the wheel so adjacent thumbnails stay distinct; the
    // same running counter doubles as the index shown on the tile.
    final index = _nextHue;
    final hue = (index * 47) % 360;
    _nextHue++;
    return Photo(id: id, index: index, hue: hue.toDouble());
  }

  List<PhotoSection> _seedSections() => [
    PhotoSection(
      id: 'today',
      title: 'Today',
      photos: [for (var i = 0; i < 8; i++) _makePhoto('today-$i')],
    ),
    PhotoSection(
      id: 'yesterday',
      title: 'Yesterday',
      photos: [for (var i = 0; i < 17; i++) _makePhoto('yesterday-$i')],
    ),
    PhotoSection(
      id: 'week',
      title: 'Last Week',
      photos: [for (var i = 0; i < 29; i++) _makePhoto('week-$i')],
    ),
    PhotoSection(
      id: 'month',
      title: 'Last Month',
      photos: [for (var i = 0; i < 42; i++) _makePhoto('month-$i')],
    ),
    PhotoSection(
      id: 'year',
      title: 'Last Year',
      photos: [for (var i = 0; i < 60; i++) _makePhoto('year-$i')],
    ),
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
            Text(
              'Library',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            Text(
              'Pinch to zoom · long-press to move',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Lazy sliver gallery',
            icon: const Icon(Icons.view_comfy_alt),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SliverGalleryPage(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Measured text cards',
            icon: const Icon(Icons.notes),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MeasuredNotesPage(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Device photos',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevicePhotosPage()),
            ),
          ),
        ],
        bottom: _ControlsBar(
          style: _zoomStyle,
          columns: _columns,
          minColumns: _zoomLevels.first,
          maxColumns: _zoomLevels.last,
          levels: _zoomLevels,
          onStyleChanged: (style) => setState(() => _zoomStyle = style),
          onColumnsChanged: (columns) => setState(() => _columns = columns),
        ),
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
            zoomConfig: GridZoomConfig(
              zoomLevels: _zoomLevels,
              style: _zoomStyle,
            ),
            onCrossAxisCountChanged: (count) =>
                setState(() => _columns = count),
            onReorderFinished: _onReorderFinished,
            sections: [
              for (final section in _sections)
                GridSection(
                  id: section.id,
                  items: section.photos,
                  header: _SectionHeader(
                    title: section.title,
                    count: section.photos.length,
                  ),
                ),
            ],
            liftedBuilder: (context, photo, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: child,
              ),
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
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: hueGradient(photo.hue)),
        child: Stack(
          children: [
            // The index number, sized with the tile so it stays readable at
            // every zoom level.
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                  child: Text(
                    '${photo.index}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      shadows: [
                        Shadow(color: Color(0x66000000), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _iconFor(photo.hue),
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(double hue) {
    const icons = [
      Icons.landscape,
      Icons.pets,
      Icons.local_cafe,
      Icons.beach_access,
      Icons.park,
      Icons.camera_alt,
    ];
    return icons[(hue ~/ 47).toInt() % icons.length];
  }
}

/// A large collection rendered lazily with [SliverFluidGrid] inside a
/// [CustomScrollView], alongside a real [SliverAppBar]. Only the tiles near the
/// viewport are built, so thousands of items scroll smoothly. Pinch to zoom and
/// long-press to reorder work exactly as in the box grid.
class SliverGalleryPage extends StatefulWidget {
  const SliverGalleryPage({super.key});

  @override
  State<SliverGalleryPage> createState() => _SliverGalleryPageState();
}

class _SliverGalleryPageState extends State<SliverGalleryPage> {
  /// The only column counts the pinch can rest on, iOS-Photos style.
  static const _zoomLevels = [1, 3, 5, 7, 9];

  int _columns = 3;
  late final List<PhotoSection> _sections = _seedSections();

  List<PhotoSection> _seedSections() => [
    for (var s = 0; s < 6; s++)
      PhotoSection(
        id: 'batch-$s',
        title: 'Batch ${s + 1}',
        photos: [
          for (var i = 0; i < 350; i++)
            Photo(
              id: '$s-$i',
              index: s * 350 + i,
              hue: ((s * 350 + i) * 47 % 360).toDouble(),
            ),
        ],
      ),
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
    final total = _sections.fold<int>(
      0,
      (sum, section) => sum + section.photos.length,
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text('$total photos · $_columns cols'),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(20),
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Lazy sliver · pinch to zoom · long-press to move',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          SliverFluidGrid<Photo>(
            crossAxisCount: _columns,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            idOf: (photo) => photo.id,
            // Discrete levels + the canvas crossfade = the iOS Photos zoom:
            // the pinch morphs between adjacent levels, new tiles slide in
            // from the edges already rendered, and on-screen positions swap
            // content with a fade.
            zoomConfig: const GridZoomConfig(
              zoomLevels: _zoomLevels,
              style: GridZoomStyle.photos,
            ),
            onCrossAxisCountChanged: (count) =>
                setState(() => _columns = count),
            onReorderFinished: _onReorderFinished,
            // Tiles are square, so the height equals the column width.
            itemHeight: GridItemHeight.builder((photo, itemWidth) => itemWidth),
            sections: [
              for (final section in _sections)
                GridSection(
                  id: section.id,
                  items: section.photos,
                  header: _SectionHeader(
                    title: section.title,
                    count: section.photos.length,
                  ),
                ),
            ],
            liftedBuilder: (context, photo, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: child,
              ),
            ),
            itemBuilder: (context, photo) => _PhotoTile(photo: photo),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Loads the device's real photo library and lays it out lazily with
/// [SliverFluidGrid] in the iOS-Photos [GridZoomStyle.photos] transition. This
/// is the only page backed by real images (via `photo_manager`); the others use
/// generated gradient stand-ins. Permission is requested on entry, and the
/// mode + column controls behave exactly as on the other pages.
class DevicePhotosPage extends StatefulWidget {
  const DevicePhotosPage({super.key});

  @override
  State<DevicePhotosPage> createState() => _DevicePhotosPageState();
}

enum _PhotoLoadState { loading, denied, empty, ready }

class _DevicePhotosPageState extends State<DevicePhotosPage> {
  /// The only column counts the pinch can rest on, iOS-Photos style.
  static const _zoomLevels = [1, 3, 5, 7, 9, 11, 13, 15];

  int _columns = 3;
  GridZoomStyle _zoomStyle = GridZoomStyle.photos;

  _PhotoLoadState _state = _PhotoLoadState.loading;
  List<AssetEntity> _photos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _PhotoLoadState.loading);

    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!permission.hasAccess) {
      setState(() => _state = _PhotoLoadState.denied);
      return;
    }

    // The single "all photos" album, newest first (photo_manager's default).
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() => _state = _PhotoLoadState.empty);
      return;
    }

    final album = albums.first;
    final count = await album.assetCountAsync;
    final photos = await album.getAssetListRange(start: 0, end: count);
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _state = photos.isEmpty ? _PhotoLoadState.empty : _PhotoLoadState.ready;
    });
  }

  void _onReorderFinished(GridReorderResult<AssetEntity> result) {
    setState(() => _photos = result.itemsOf('device'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Text(
            _state == _PhotoLoadState.ready
                ? '${_photos.length} device photos'
                : 'Device photos',
          ),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
          bottom: _state == _PhotoLoadState.ready
              ? _ControlsBar(
                  style: _zoomStyle,
                  columns: _columns,
                  minColumns: _zoomLevels.first,
                  maxColumns: _zoomLevels.last,
                  levels: _zoomLevels,
                  onStyleChanged: (style) => setState(() => _zoomStyle = style),
                  onColumnsChanged: (columns) =>
                      setState(() => _columns = columns),
                )
              : null,
        ),
        ..._body(),
      ],
    ),
  );

  List<Widget> _body() {
    switch (_state) {
      case _PhotoLoadState.loading:
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      case _PhotoLoadState.denied:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyMessage(
              icon: Icons.lock_outline,
              text: 'Photo access is needed to show your library.',
              actionLabel: 'Open Settings',
              onAction: PhotoManager.openSetting,
            ),
          ),
        ];
      case _PhotoLoadState.empty:
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyMessage(
              icon: Icons.photo_library_outlined,
              text: 'No photos found on this device.',
            ),
          ),
        ];
      case _PhotoLoadState.ready:
        return [
          SliverFluidGrid<AssetEntity>(
            crossAxisCount: _columns,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            padding: const EdgeInsets.symmetric(horizontal: 1),
            idOf: (photo) => photo.id,
            zoomConfig: GridZoomConfig(
              zoomLevels: _zoomLevels,
              style: _zoomStyle,
            ),
            onCrossAxisCountChanged: (count) =>
                setState(() => _columns = count),
            onReorderFinished: _onReorderFinished,
            // Square tiles, so the height equals the column width.
            itemHeight: GridItemHeight.builder((photo, itemWidth) => itemWidth),
            sections: [GridSection(id: 'device', items: _photos)],
            liftedBuilder: (context, photo, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: child,
              ),
            ),
            itemBuilder: (context, photo) => _DevicePhotoTile(entity: photo),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ];
    }
  }
}

/// A square thumbnail backed by a real [AssetEntity]. The thumbnail size is
/// fixed (independent of the zoom level) so the decoded image is cached once
/// and reused across every column count: during a photos-style pinch the
/// incoming grid is a freshly-built copy, and a same-size cache hit lets it
/// paint synchronously instead of flashing a placeholder. 300 is kept modest
/// (crisp at the default 3–5 columns) so the dense 9-column set stays well
/// inside the enlarged image cache — see the note in `main()`.
class _DevicePhotoTile extends StatelessWidget {
  const _DevicePhotoTile({required this.entity});

  final AssetEntity entity;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: AssetEntityImage(
      entity,
      isOriginal: false,
      thumbnailSize: const ThumbnailSize.square(300),
      fit: BoxFit.cover,
      // Keep the last frame if a tile is ever re-resolved, rather than briefly
      // clearing to the placeholder.
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const ColoredBox(color: Color(0x11000000));
      },
    ),
  );
}

/// A centred icon + message with an optional action, for the empty/denied
/// states of [DevicePhotosPage].
class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A note with variable-length body text and an optional photo, so its rendered
/// height is not known up front — the case for [GridItemHeight.measured]. The
/// mix of photo/no-photo and short/long bodies makes every card a different
/// height, which is exactly what the measured layout is for.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.hue,
  });

  final String id;
  final String title;
  final String body;

  /// The hue of the card's header photo, or null for a text-only note.
  final double? hue;
}

/// A masonry board of variable-height text cards laid out with
/// `GridItemHeight.measured()`: heights come from the rendered content, so no
/// height callback is needed. Only the cards near the viewport are built and
/// measured; the rest are estimated and self-correct as they scroll in.
class MeasuredNotesPage extends StatefulWidget {
  const MeasuredNotesPage({super.key});

  @override
  State<MeasuredNotesPage> createState() => _MeasuredNotesPageState();
}

class _MeasuredNotesPageState extends State<MeasuredNotesPage> {
  static const _lorem =
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod '
      'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, '
      'quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo.';

  late final List<Note> _notes = [
    for (var i = 0; i < 300; i++)
      Note(
        id: 'n$i',
        title: 'Note ${i + 1}',
        // Vary the body length so heights genuinely differ.
        body: _lorem.substring(0, 30 + (i * 37) % (_lorem.length - 30)),
        // Two in every three notes carry a photo; the rest are text-only.
        hue: i % 3 == 0 ? null : ((i * 47) % 360).toDouble(),
      ),
  ];

  static const _minColumns = 1;
  static const _maxColumns = 6;

  int _columns = 2;
  GridZoomStyle _zoomStyle = GridZoomStyle.morph;

  void _onReorderFinished(GridReorderResult<Note> result) {
    setState(
      () => _notes
        ..clear()
        ..addAll(result.itemsOf('notes')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Text('${_notes.length} notes · measured heights'),
          bottom: _ControlsBar(
            style: _zoomStyle,
            columns: _columns,
            minColumns: _minColumns,
            maxColumns: _maxColumns,
            onStyleChanged: (style) => setState(() => _zoomStyle = style),
            onColumnsChanged: (columns) => setState(() => _columns = columns),
          ),
        ),
        SliverFluidGrid<Note>(
          crossAxisCount: _columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          padding: const EdgeInsets.all(8),
          idOf: (note) => note.id,
          zoomConfig: GridZoomConfig(
            minCrossAxisCount: _minColumns,
            maxCrossAxisCount: _maxColumns,
            style: _zoomStyle,
          ),
          onCrossAxisCountChanged: (count) => setState(() => _columns = count),
          onReorderFinished: _onReorderFinished,
          // No itemHeightBuilder: heights are measured from the cards.
          itemHeight: const GridItemHeight.measured(),
          sections: [GridSection(id: 'notes', items: _notes)],
          itemBuilder: (context, note) => _NoteCard(note: note),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    ),
  );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note.hue case final hue?)
            AspectRatio(
              aspectRatio: 3 / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: hueGradient(hue)),
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.image_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(note.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(note.body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The gradient used for every stand-in thumbnail, so photo tiles and note
/// cards share one look. A hue fully determines the two-stop gradient.
LinearGradient hueGradient(double hue) {
  final base = HSLColor.fromAHSL(1, hue, 0.62, 0.55).toColor();
  final light = HSLColor.fromAHSL(1, (hue + 24) % 360, 0.7, 0.68).toColor();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [light, base],
  );
}

/// The mode + column controls shared by both grid pages, shown under the app
/// bar. Changing the mode swaps the pinch transition live; the stepper drives
/// the column count programmatically (the grid morphs to it exactly as a pinch
/// would), and reflects back the count a pinch settles on.
class _ControlsBar extends StatelessWidget implements PreferredSizeWidget {
  const _ControlsBar({
    required this.style,
    required this.columns,
    required this.minColumns,
    required this.maxColumns,
    required this.onStyleChanged,
    required this.onColumnsChanged,
    this.levels,
  });

  final GridZoomStyle style;
  final int columns;
  final int minColumns;
  final int maxColumns;
  final ValueChanged<GridZoomStyle> onStyleChanged;
  final ValueChanged<int> onColumnsChanged;

  /// The discrete `zoomLevels` the stepper snaps to, or null for a continuous
  /// [[minColumns], [maxColumns]] range.
  final List<int>? levels;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _ZoomModeButton(style: style, onChanged: onStyleChanged),
          const Spacer(),
          _ColumnStepper(
            columns: columns,
            min: minColumns,
            max: maxColumns,
            onChanged: onColumnsChanged,
            levels: levels,
          ),
        ],
      ),
    ),
  );
}

/// A dropdown over the [GridZoomStyle] values, labelled with the current one.
class _ZoomModeButton extends StatelessWidget {
  const _ZoomModeButton({required this.style, required this.onChanged});

  final GridZoomStyle style;
  final ValueChanged<GridZoomStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<GridZoomStyle>(
      tooltip: 'Zoom mode',
      initialValue: style,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final value in GridZoomStyle.values)
          PopupMenuItem<GridZoomStyle>(value: value, child: Text(value.name)),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'mode: ${style.name}',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(Icons.arrow_drop_down, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

/// A compact − N + control. Without [levels] it steps by one within
/// [[min], [max]]; with [levels] (discrete `zoomLevels`) it snaps to the
/// adjacent allowed level, so it can never produce a count the grid disallows.
class _ColumnStepper extends StatelessWidget {
  const _ColumnStepper({
    required this.columns,
    required this.min,
    required this.max,
    required this.onChanged,
    this.levels,
  });

  final int columns;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final List<int>? levels;

  /// The ascending stops the − / + buttons move between.
  List<int> get _stops => levels ?? [for (var c = min; c <= max; c++) c];

  /// The largest stop below the current count, or null (button disabled).
  int? get _lower =>
      _stops.where((stop) => stop < columns).fold<int?>(null, (a, b) => b);

  /// The smallest stop above the current count, or null (button disabled).
  int? get _higher =>
      _stops.where((stop) => stop > columns).fold<int?>(null, (a, b) => a ?? b);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = _lower;
    final higher = _higher;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Fewer columns',
          onPressed: lower == null ? null : () => onChanged(lower),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$columns cols',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'More columns',
          onPressed: higher == null ? null : () => onChanged(higher),
          icon: const Icon(Icons.add),
        ),
      ],
    );
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
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    ),
  );
}
