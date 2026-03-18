import 'package:flutter/material.dart';
import 'package:spark/shared/widgets/kyc_feature_gate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:spark/core/models/user_profile.dart';
import 'package:spark/core/services/user_api_service.dart';

import '../widgets/nearby_profile_card.dart';

// India center – initial map view
const LatLng _indiaCenter = LatLng(20.5937, 78.9629);
const double _indiaZoom = 5.0;
const double _userZoom = 14.0;

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final UserApiService _userApi = UserApiService();
  List<NearbyUser> _nearbyProfiles = [];
  bool _locationVisible = false;
  String _locationLabel = 'Location hidden';
  bool _nearbyLoading = true;
  String? _nearbyError;

  @override
  void initState() {
    super.initState();
    _loadMyLocationSetting();
  }

  Future<void> _loadMyLocationSetting() async {
    try {
      final me = await _userApi.getMe();
      final visible = me['locationVisible'] == true;
      setState(() {
        _locationVisible = visible;
        _locationLabel = visible ? 'Your location visible on map' : 'Location hidden';
      });
    } catch (_) {
      setState(() => _locationLabel = 'Location hidden');
    }
  }

  void _onMapReady(LatLng? userPosition, List<NearbyUser> nearby) {
    setState(() {
      _nearbyProfiles = nearby;
      _nearbyLoading = false;
      _nearbyError = null;
    });
  }

  void _onMapError(String? error) {
    setState(() {
      _nearbyLoading = false;
      _nearbyError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KycFeatureGate(
      child: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Nearby you'),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurface),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: theme.colorScheme.onSurface),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LocationChip(
            location: _locationLabel,
            locationVisible: _locationVisible,
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
            child: _MapSection(
              theme: theme,
              locationVisible: _locationVisible,
              onReady: _onMapReady,
              onError: _onMapError,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Nearby',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 3,
            child: _nearbyLoading
                ? const Center(child: CircularProgressIndicator())
                : _nearbyError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _nearbyError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        scrollDirection: Axis.horizontal,
                        itemCount: _nearbyProfiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final p = _nearbyProfiles[index];
                          final distanceStr = p.distanceKm < 1
                              ? '${(p.distanceKm * 1000).round()} m'
                              : '${p.distanceKm.toStringAsFixed(1)} Km';
                          return NearbyProfileCard(
                            name: p.displayName ?? 'Someone',
                            age: '',
                            distance: distanceStr,
                            location: 'Nearby',
                            imageUrl: p.primaryPhotoUrl.isNotEmpty ? p.primaryPhotoUrl : null,
                            onTap: () {},
                            onLike: () {},
                            onMessage: () {},
                          );
                        },
                      ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({
    required this.location,
    this.locationVisible = false,
  });

  final String location;
  final bool locationVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                locationVisible ? Icons.location_on_rounded : Icons.location_off_rounded,
                size: 18,
                color: locationVisible ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapSection extends StatefulWidget {
  const _MapSection({
    required this.theme,
    required this.locationVisible,
    required this.onReady,
    required this.onError,
  });

  final ThemeData theme;
  final bool locationVisible;
  final void Function(LatLng? userPosition, List<NearbyUser> nearby) onReady;
  final void Function(String? error) onError;

  @override
  State<_MapSection> createState() => _MapSectionState();
}

class _MapSectionState extends State<_MapSection> {
  final MapController _mapController = MapController();
  final UserApiService _userApi = UserApiService();
  LatLng? _userPosition;
  List<NearbyUser> _nearby = [];
  bool _locationLoading = true;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _fetchUserLocationAndNearby();
  }

  Future<void> _fetchUserLocationAndNearby() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationLoading = false;
          _locationError = 'Location service disabled';
        });
        widget.onError('Location service disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _locationLoading = false;
          _locationError = 'Location permission denied';
        });
        widget.onError('Location permission denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final userLatLng = LatLng(position.latitude, position.longitude);

      if (widget.locationVisible) {
        try {
          await _userApi.updateMe(
            latitude: position.latitude,
            longitude: position.longitude,
          );
        } catch (_) {}
      }

      List<NearbyUser> nearby = [];
      try {
        nearby = await _userApi.getNearby(
          latitude: position.latitude,
          longitude: position.longitude,
          radiusKm: 100,
          limit: 50,
        );
      } catch (e) {
        widget.onError(e.toString());
      }

      setState(() {
        _userPosition = userLatLng;
        _nearby = nearby;
        _locationLoading = false;
        _locationError = null;
      });
      widget.onReady(userLatLng, nearby);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(userLatLng, _userZoom);
      });
    } on MissingPluginException {
      setState(() {
        _locationLoading = false;
        _locationError = 'Location not available. Rebuild the app (flutter run).';
      });
      widget.onError('Location not available');
    } catch (e) {
      setState(() {
        _locationLoading = false;
        _locationError = 'Could not get location';
      });
      widget.onError('Could not get location');
    }
  }

  void _moveToUser() {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, _userZoom);
    } else {
      _fetchUserLocationAndNearby();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _indiaCenter,
                  initialZoom: _indiaZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.spark.spark',
                  ),
                  if (_userPosition != null && widget.locationVisible)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _userPosition!,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                'You',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_nearby.isNotEmpty)
                    MarkerLayer(
                      markers: _nearby
                          .where((u) => u.latitude != null && u.longitude != null)
                          .map((u) => Marker(
                                point: LatLng(u.latitude!, u.longitude!),
                                width: 36,
                                height: 36,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.tertiaryContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.tertiary,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      (u.displayName ?? '?').isNotEmpty
                                          ? (u.displayName!.length > 1 ? u.displayName!.substring(0, 1).toUpperCase() : '?')
                                          : '?',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                ],
              ),
              if (_locationLoading)
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.7),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: theme.colorScheme.primary),
                          const SizedBox(height: 12),
                          Text(
                            'Getting your location…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_locationError != null && !_locationLoading)
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Material(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        _locationError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                left: 12,
                child: _MapControlButton(
                  icon: Icons.my_location_rounded,
                  onPressed: _moveToUser,
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _MapControlButton(
                  icon: Icons.filter_list_rounded,
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: theme.colorScheme.shadow,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
