import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/features/rooms/data/room_models.dart';
import 'package:spark/features/rooms/data/rooms_api_service.dart';

/// Multi-step room creation: activity → place → type (personal/group) → tags.
/// Women or premium male users can create (enforced on backend).
class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int _step = 0;
  final PageController _pageController = PageController();
  final RoomsApiService _api = RoomsApiService();
  bool _submitting = false;

  // Step 1
  String? _activityType;
  String _activityLabel = '';
  String _activityEmoji = '☕';

  // Step 2
  final _placeNameController = TextEditingController();
  final _placeAddressController = TextEditingController();

  // Step 3
  RoomType _roomType = RoomType.personal;
  int _maxParticipants = 2;

  // Step 4
  final List<String> _selectedTags = [];
  final _titleController = TextEditingController();
  DateTime _eventAt = DateTime.now().add(const Duration(days: 1));

  @override
  void dispose() {
    _pageController.dispose();
    _placeNameController.dispose();
    _placeAddressController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onActivitySelected(String id, String label, String emoji) {
    setState(() {
      _activityType = id;
      _activityLabel = label;
      _activityEmoji = emoji;
    });
  }

  void _nextStep() {
    if (_step < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _backStep() {
    if (_step > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_canProceed) return;
    final title = _titleController.text.trim();
    final placeName = _placeNameController.text.trim();
    final placeAddress = _placeAddressController.text.trim();
    setState(() => _submitting = true);
    try {
      await _api.createRoom(
        title: title,
        activityType: _activityType!,
        activityLabel: _activityLabel,
        activityEmoji: _activityEmoji,
        placeName: placeName,
        placeAddress: placeAddress.isNotEmpty ? placeAddress : null,
        roomType: _roomType.value,
        maxParticipants: _maxParticipants,
        tags: _selectedTags.isEmpty ? null : _selectedTags,
        eventAt: _eventAt.toIso8601String(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meetup created! You can now accept join requests.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppConstants.routeRooms);
    } on RoomsApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return _activityType != null;
      case 1:
        return _placeNameController.text.trim().isNotEmpty;
      case 2:
        return true;
      case 3:
        return _titleController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _backStep,
        ),
        title: Text('Create meetup ${_step + 1}/4'),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                _Step1ChooseActivity(
                  selectedId: _activityType,
                  onSelected: _onActivitySelected,
                ),
                _Step2ChoosePlace(
                  placeNameController: _placeNameController,
                  placeAddressController: _placeAddressController,
                ),
                _Step3Participants(
                  roomType: _roomType,
                  maxParticipants: _maxParticipants,
                  onRoomTypeChanged: (v) => setState(() => _roomType = v),
                  onMaxChanged: (v) => setState(() => _maxParticipants = v),
                ),
                _Step4TagsAndTime(
                  titleController: _titleController,
                  eventAt: _eventAt,
                  selectedTags: _selectedTags,
                  tagSuggestions: AppConstants.roomTagSuggestions,
                  onEventAtChanged: (v) => setState(() => _eventAt = v),
                  onTagToggled: (tag) {
                    setState(() {
                      if (_selectedTags.contains(tag)) {
                        _selectedTags.remove(tag);
                      } else {
                        _selectedTags.add(tag);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_canProceed && !_submitting) ? _nextStep : null,
                  child: _submitting && _step == 3
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_step == 3 ? 'Create meetup' : 'Next'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step1ChooseActivity extends StatelessWidget {
  const _Step1ChooseActivity({
    required this.selectedId,
    required this.onSelected,
  });

  final String? selectedId;
  final void Function(String id, String label, String emoji) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose activity',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'What kind of experience do you want to host?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: AppConstants.roomActivityTypes.map((a) {
              final id = a['id']!;
              final label = a['label']!;
              final emoji = a['emoji']!;
              final selected = selectedId == id;
              return Material(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => onSelected(id, label, emoji),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Step2ChoosePlace extends StatelessWidget {
  const _Step2ChoosePlace({
    required this.placeNameController,
    required this.placeAddressController,
  });

  final TextEditingController placeNameController;
  final TextEditingController placeAddressController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where?',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Restaurant, cafe, trail, or venue name',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: placeNameController,
            decoration: const InputDecoration(
              labelText: 'Place name',
              hintText: 'e.g. Starbucks Bandra, Lonavala Trail',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: placeAddressController,
            decoration: const InputDecoration(
              labelText: 'Address or area',
              hintText: 'e.g. Bandra West, Mumbai',
            ),
          ),
        ],
      ),
    );
  }
}

class _Step3Participants extends StatelessWidget {
  const _Step3Participants({
    required this.roomType,
    required this.maxParticipants,
    required this.onRoomTypeChanged,
    required this.onMaxChanged,
  });

  final RoomType roomType;
  final int maxParticipants;
  final ValueChanged<RoomType> onRoomTypeChanged;
  final ValueChanged<int> onMaxChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Room type',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Personal: one-on-one with you. Group: multiple people can join.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          RadioListTile<RoomType>(
            value: RoomType.personal,
            groupValue: roomType,
            onChanged: (v) => v != null ? onRoomTypeChanged(v) : null,
            title: const Text('Personal (1 person)'),
            subtitle: const Text('They chat with you one-on-one'),
          ),
          RadioListTile<RoomType>(
            value: RoomType.group,
            groupValue: roomType,
            onChanged: (v) => v != null ? onRoomTypeChanged(v) : null,
            title: const Text('Group (2–8 people)'),
            subtitle: const Text('Group chat with everyone'),
          ),
          if (roomType == RoomType.group) ...[
            const SizedBox(height: 24),
            Text(
              'Max participants',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filled(
                  onPressed: maxParticipants > 2
                      ? () => onMaxChanged(maxParticipants - 1)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '$maxParticipants',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: maxParticipants < 8
                      ? () => onMaxChanged(maxParticipants + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Step4TagsAndTime extends StatelessWidget {
  const _Step4TagsAndTime({
    required this.titleController,
    required this.eventAt,
    required this.selectedTags,
    required this.tagSuggestions,
    required this.onEventAtChanged,
    required this.onTagToggled,
  });

  final TextEditingController titleController;
  final DateTime eventAt;
  final List<String> selectedTags;
  final List<String> tagSuggestions;
  final ValueChanged<DateTime> onEventAtChanged;
  final ValueChanged<String> onTagToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Name & time',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Give your room a title and when it happens.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Room title',
              hintText: 'e.g. Coffee at Bandra, Sunset Hike',
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date & time'),
            subtitle: Text(
              '${eventAt.day}/${eventAt.month}/${eventAt.year} · ${eventAt.hour}:${eventAt.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today_rounded),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: eventAt,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null && context.mounted) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(eventAt),
                );
                if (time != null) {
                  onEventAtChanged(DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ));
                }
              }
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Tags',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tagSuggestions.map((tag) {
              final selected = selectedTags.contains(tag);
              return FilterChip(
                label: Text('#$tag'),
                selected: selected,
                onSelected: (_) => onTagToggled(tag),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
