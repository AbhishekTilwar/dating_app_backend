import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/core/models/user_profile.dart';
import 'package:spark/core/services/user_profile_service.dart';

/// Login → profile creation: name, photos (Storage), prompts, goal, opening move.
/// Saves to Firestore on each step; final step sets [profileComplete].
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  final _profile = UserProfileService();
  final _picker = ImagePicker();

  int _step = 0;
  static const int _totalSteps = 5;

  final List<String> _photoUrls = [];
  int? _uploadingIndex;
  final List<ProfilePrompt> _prompts = [];
  String? _selectedGoal;
  String? _openingMove;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadError = 'Please sign in first');
      return;
    }
    await _profile.ensureUserDocument(FirebaseAuth.instance.currentUser!);
    final p = await _profile.getProfile(uid);
    if (!mounted || p == null) return;
    setState(() {
      _nameController.text = p.displayName ?? '';
      _photoUrls.clear();
      _photoUrls.addAll(p.photos);
      _prompts.clear();
      _prompts.addAll(p.prompts);
      _selectedGoal = p.relationshipGoal;
      _openingMove = p.openingMove;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// [index] is position to replace, or equals [ _photoUrls.length ] to append.
  Future<void> _pickPhoto(int index) async {
    final uid = _uid;
    if (uid == null) return;
    if (index < _photoUrls.length) {
      // replace existing
    } else if (_photoUrls.length >= AppConstants.maxPhotosPerProfile) {
      return;
    }
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (x == null || !mounted) return;
    setState(() => _uploadingIndex = index);
    try {
      final url = await _profile.uploadProfilePhoto(uid, x);
      if (!mounted) return;
      setState(() {
        if (index < _photoUrls.length) {
          _photoUrls[index] = url;
        } else {
          _photoUrls.add(url);
        }
      });
      await _profile.mergeProfileFields(uid: uid, photos: List<String>.from(_photoUrls));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingIndex = null);
    }
  }

  Future<void> _persistStep() async {
    final uid = _uid;
    if (uid == null) return;
    switch (_step) {
      case 0:
        await _profile.mergeProfileFields(
          uid: uid,
          displayName: _nameController.text,
          photos: List<String>.from(_photoUrls),
        );
        break;
      case 1:
        await _profile.mergeProfileFields(uid: uid, prompts: List<ProfilePrompt>.from(_prompts));
        break;
      case 2:
        if (_selectedGoal != null) {
          await _profile.mergeProfileFields(uid: uid, relationshipGoal: _selectedGoal);
        }
        break;
      case 3:
        if (_openingMove != null) {
          await _profile.mergeProfileFields(uid: uid, openingMove: _openingMove);
        }
        break;
    }
  }

  Future<void> _next() async {
    final uid = _uid;
    if (uid == null) {
      context.go('/auth');
      return;
    }

    if (_step == 0) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add your display name')),
        );
        return;
      }
      if (_photoUrls.length < AppConstants.minPhotosRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Add at least ${AppConstants.minPhotosRequired} photos '
              '(${_photoUrls.length}/${AppConstants.minPhotosRequired})',
            ),
          ),
        );
        return;
      }
    }

    if (_step == 1 && _prompts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Answer at least one prompt')),
      );
      return;
    }

    if (_step == 2 && _selectedGoal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose what you\'re looking for')),
      );
      return;
    }

    if (_step == 3 && _openingMove == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick an opening move')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _persistStep();
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (_step < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _step++);
    } else {
      setState(() => _saving = true);
      try {
        await _profile.mergeProfileFields(
          uid: uid,
          displayName: _nameController.text.trim(),
          photos: List<String>.from(_photoUrls),
          prompts: List<ProfilePrompt>.from(_prompts),
          relationshipGoal: _selectedGoal,
          openingMove: _openingMove,
          profileComplete: true,
        );
        if (mounted) context.go('/kyc');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\'t save: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  void _openPromptEditor([ProfilePrompt? existing]) {
    String question = existing?.question ?? AppConstants.profilePrompts.first;
    final answerController = TextEditingController(text: existing?.answer ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your answer',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Prompt',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: question,
                        items: AppConstants.profilePrompts
                            .map((p) =>
                                DropdownMenuItem(value: p, child: Text(p, maxLines: 2)))
                            .toList(),
                        onChanged: (v) => setModalState(() => question = v ?? question),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: answerController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Share something genuine…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      final a = answerController.text.trim();
                      if (a.isEmpty) return;
                      if (existing == null &&
                          _prompts.length >= AppConstants.maxPromptAnswers) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Maximum ${AppConstants.maxPromptAnswers} prompts',
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        if (existing != null) {
                          final i = _prompts.indexOf(existing);
                          if (i >= 0) {
                            _prompts[i] = ProfilePrompt(question: question, answer: a);
                          }
                        } else {
                          _prompts.add(ProfilePrompt(question: question, answer: a));
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save prompt'),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/auth'),
                  child: const Text('Go to sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _saving
                    ? null
                    : () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                        setState(() => _step--);
                      },
              )
            : null,
        title: Text('Step ${_step + 1} of $_totalSteps'),
      ),
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildNameAndPhotosStep(theme),
            _buildPromptsStep(theme),
            _buildGoalStep(theme),
            _buildOpeningMoveStep(theme),
            _buildReviewStep(theme),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton(
            onPressed: _saving ? null : _next,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_step == _totalSteps - 1 ? 'Finish & go to Crossed' : 'Continue'),
          ),
        ),
      ),
    );
  }

  Widget _buildNameAndPhotosStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your name & photos',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ).animate().fadeIn().slideY(begin: 0.05, end: 0),
          const SizedBox(height: 8),
          Text(
            'Shown on your profile. At least ${AppConstants.minPhotosRequired} photos.',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              const count = 3;
              final size = (constraints.maxWidth - spacing * (count - 1)) / count;
              final maxP = AppConstants.maxPhotosPerProfile;
              final n = _photoUrls.length;
              final slotCount = n < maxP ? n + 1 : n;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: List.generate(slotCount, (i) {
                  final isAdd = i == _photoUrls.length;
                  final uploading = _uploadingIndex == i;
                  return SizedBox(
                    width: size,
                    height: size,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: uploading || _uploadingIndex != null
                            ? null
                            : () => _pickPhoto(i),
                        child: uploading
                            ? const Center(child: CircularProgressIndicator())
                            : !isAdd
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: _photoUrls[i],
                                        fit: BoxFit.cover,
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: IconButton.filledTonal(
                                          icon: const Icon(Icons.close, size: 18),
                                          onPressed: () {
                                            setState(() => _photoUrls.removeAt(i));
                                            final u = _uid;
                                            if (u != null) {
                                              _profile.mergeProfileFields(
                                                uid: u,
                                                photos: List<String>.from(_photoUrls),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined,
                                          size: 36, color: theme.colorScheme.primary),
                                      Text('Add', style: theme.textTheme.labelMedium),
                                    ],
                                  ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPromptsStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Answer prompts',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Up to ${AppConstants.maxPromptAnswers}. They show on your profile in real time.',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_prompts.isEmpty)
            OutlinedButton.icon(
              onPressed: () => _openPromptEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a prompt'),
            )
          else
            ..._prompts.map((p) {
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(p.question, style: theme.textTheme.labelMedium),
                  subtitle: Text(p.answer),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openPromptEditor(p),
                  ),
                ),
              );
            }),
          if (_prompts.isNotEmpty && _prompts.length < AppConstants.maxPromptAnswers)
            TextButton.icon(
              onPressed: () => _openPromptEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Add another'),
            ),
        ],
      ),
    );
  }

  Widget _buildGoalStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What are you looking for?',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ...AppConstants.relationshipGoals.map((goal) {
            final selected = _selectedGoal == goal;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilterChip(
                label: Text(goal),
                selected: selected,
                onSelected: (_) => setState(() => _selectedGoal = goal),
                showCheckmark: true,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOpeningMoveStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your opening move',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ...AppConstants.defaultOpeningMoves.map((move) {
            final selected = _openingMove == move;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(move),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: selected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : theme.colorScheme.surfaceContainerHighest,
                selected: selected,
                onTap: () => setState(() => _openingMove = move),
                leading: Icon(
                  selected ? Icons.check_circle : Icons.chat_bubble_outline_rounded,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildReviewStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You\'re all set',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap Finish to start discovering. You can edit your profile anytime.',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text(_nameController.text.trim(), style: theme.textTheme.titleLarge),
          Text(_selectedGoal ?? '', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: _photoUrls[i], width: 88, height: 88, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
