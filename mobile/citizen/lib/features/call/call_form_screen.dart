import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jardem_core/jardem_core.dart';

import '../../shared/dial.dart';
import '../../shared/widgets.dart';
import '../../state/incidents.dart';
import '../../state/location.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import 'triage_hint.dart';

/// A locally kept attachment (never uploaded in the demo).
class PickedMedia {
  const PickedMedia({required this.name, this.bytes});

  final String name;

  /// Image bytes for the thumbnail; null for videos.
  final Uint8List? bytes;
}

/// Picks photos / videos; overridable in tests.
final mediaPickerProvider = Provider<Future<List<PickedMedia>> Function()>(
  (ref) => () async {
    final files = await ImagePicker().pickMultipleMedia(limit: 6, imageQuality: 70, maxWidth: 1600);
    final out = <PickedMedia>[];
    for (final f in files) {
      final mime = f.mimeType ?? '';
      final isVideo = mime.startsWith('video/') || RegExp(r'\.(mp4|mov|webm|mkv|avi)$').hasMatch(f.name.toLowerCase());
      out.add(PickedMedia(name: f.name, bytes: isVideo ? null : await f.readAsBytes()));
    }
    return out;
  },
);

/// Russian message for a failed `POST /incidents`.
String createIncidentError(Object e) {
  if (e is ApiException) {
    if (e.isUnprocessable) {
      return 'Адрес вне зоны обслуживания. Платформа работает только в пределах Алматы — выберите точку в городе.';
    }
    if (e.isRateLimited) {
      return 'У вас уже 3 активных вызова. Дождитесь завершения или отмените один из них.';
    }
  }
  return errorMessage(e);
}

/// «Вызов скорой помощи»: category, description with live triage, media,
/// address, contact phone and the red call button.
class CallFormScreen extends ConsumerStatefulWidget {
  const CallFormScreen({super.key, required this.service, this.initialCategory, this.initialText});

  final ServiceType service;
  final String? initialCategory;
  final String? initialText;

  @override
  ConsumerState<CallFormScreen> createState() => _CallFormScreenState();
}

class _CallFormScreenState extends ConsumerState<CallFormScreen> {
  static const _debounce = Duration(milliseconds: 600);

  final _form = GlobalKey<FormState>();
  late final _description = TextEditingController(text: widget.initialText ?? '');
  late final TextEditingController _address;
  late final TextEditingController _phone;

  late ServiceType _service = widget.service;
  late String? _category = widget.initialCategory;
  Timer? _timer;
  int _triageSeq = 0;
  TriageResult? _triage;
  final List<PickedMedia> _media = [];
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: ref.read(locationProvider).addressPrefill);
    _phone = TextEditingController(text: ref.read(sessionProvider)?.user.phone ?? '');
    if (_description.text.trim().isNotEmpty) _runTriage();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _description.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _onDescriptionChanged(String _) {
    _timer?.cancel();
    _timer = Timer(_debounce, _runTriage);
  }

  Future<void> _runTriage() async {
    final text = _description.text.trim();
    final seq = ++_triageSeq;
    if (text.length < 4) {
      if (_triage != null) setState(() => _triage = null);
      return;
    }
    try {
      final result = await ref.read(apiClientProvider).triage(text);
      if (mounted && seq == _triageSeq) setState(() => _triage = result);
    } catch (_) {
      // The hint is optional: stay silent when triage is unavailable.
      if (mounted && seq == _triageSeq) setState(() => _triage = null);
    }
  }

  Future<void> _pickMedia() async {
    try {
      final picked = await ref.read(mediaPickerProvider)();
      if (mounted && picked.isNotEmpty) setState(() => _media.addAll(picked));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть галерею.')));
    }
  }

  Future<void> _submit(String? category) async {
    if (_submitting) return;
    if (!_form.currentState!.validate()) return;
    if (category == null) {
      setState(() => _error = 'Не удалось загрузить категории. Повторите попытку.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final incident = await ref
          .read(apiClientProvider)
          .createIncident(
            category: category,
            at: ref.read(locationProvider).point,
            address: _address.text.trim(),
            description: _description.text.trim(),
            phone: formatKzPhone(_phone.text),
          );
      ref.invalidate(incidentsProvider);
      if (mounted) context.go('/tracking/${incident.id}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = createIncidentError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final all = catalog.valueOrNull ?? const <ServiceInfo>[];
    final info = all.where((s) => s.service == _service).firstOrNull;
    final categories = info?.categories ?? const <Category>[];
    final category = info?.category(_category) ?? categories.firstOrNull;
    final location = ref.watch(locationProvider);
    final meta = ref.watch(metaProvider).valueOrNull ?? const Meta();
    final color = JardemColors.service(_service);

    return Scaffold(
      appBar: JardemAppBar(title: _service.formTitle, fallbackLocation: '/map/service/${_service.id}'),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              if (catalog.isLoading)
                const SizedBox(height: 40, child: LoadingView())
              else if (catalog.hasError)
                MessageView.error(catalog.error!, onRetry: () => ref.invalidate(catalogProvider), compact: true)
              else
                PillChips<Category>(
                  items: categories,
                  selected: category,
                  labelOf: (c) => c.shortTitle,
                  color: color,
                  outlined: true,
                  padding: EdgeInsets.zero,
                  onSelected: (c) => setState(() => _category = c.id),
                ),
              const FieldLabel('Что произошло?'),
              TextFormField(
                key: const Key('call-description'),
                controller: _description,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onDescriptionChanged,
                decoration: const InputDecoration(hintText: 'Опишите ситуацию…', counterText: ''),
              ),
              if (_triage != null)
                TriageHint(
                  triage: _triage!,
                  catalog: all,
                  currentService: _service,
                  currentCategory: category?.id,
                  onSwitch: (s, c) => setState(() {
                    _service = s;
                    _category = c;
                  }),
                ),
              const SizedBox(height: 12),
              _MediaPicker(media: _media, onAdd: _pickMedia, onRemove: (m) => setState(() => _media.remove(m))),
              const FieldLabel('Точный адрес'),
              TextFormField(
                key: const Key('call-address'),
                controller: _address,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Улица, дом, подъезд, квартира',
                  counterText: '',
                  prefixIcon: const Icon(Icons.location_on_outlined, size: 20, color: JardemColors.muted),
                  helperText: location.isDemo ? 'Демо-адрес: точка на карте — ${location.label}' : location.label,
                  helperMaxLines: 2,
                  helperStyle: JardemTheme.text(11, FontWeight.w500, color: JardemColors.muted),
                ),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Укажите адрес, чтобы экипаж быстрее вас нашёл' : null,
              ),
              const FieldLabel('Контактный телефон'),
              TextFormField(
                key: const Key('call-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '+7 777 123 45 67',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20, color: JardemColors.muted),
                ),
                validator: (v) => isValidKzPhone(v) ? null : 'Введите номер в формате +7 XXX XXX XX XX',
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Container(
                  key: const Key('call-error'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: JardemColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: JardemColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: JardemTheme.text(13, FontWeight.w600, color: const Color(0xFFB02A2A), height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              PrimaryButton(
                key: const Key('call-submit'),
                label: _service.callLabel,
                icon: Icons.emergency_share_rounded,
                color: JardemColors.danger,
                radius: 16,
                height: 54,
                loading: _submitting,
                onPressed: () => _submit(category?.id),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      kDefaultDisclaimer,
                      key: const Key('call-disclaimer'),
                      style: JardemTheme.text(11.5, FontWeight.w600, color: JardemColors.muted, height: 1.3),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => dial(context, ref, meta.emergencyPhone),
                    icon: const Icon(Icons.phone_rounded, size: 16),
                    label: Text(meta.emergencyPhone),
                    style: TextButton.styleFrom(foregroundColor: JardemColors.danger),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPicker extends StatelessWidget {
  const _MediaPicker({required this.media, required this.onAdd, required this.onRemove});

  final List<PickedMedia> media;
  final VoidCallback onAdd;
  final ValueChanged<PickedMedia> onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SecondaryButton(
        key: const Key('call-media'),
        label: 'Добавить фото / видео',
        icon: Icons.photo_camera_rounded,
        onPressed: onAdd,
      ),
      if (media.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: media.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final m = media[i];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: m.bytes == null
                        ? Container(
                            width: 64,
                            height: 64,
                            color: JardemColors.primarySoft,
                            child: const Icon(Icons.videocam_rounded, color: JardemColors.primary),
                          )
                        : Image.memory(m.bytes!, width: 64, height: 64, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: InkWell(
                      onTap: () => onRemove(m),
                      child: Container(
                        decoration: const BoxDecoration(color: Color(0xAA0F1E3D), shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Файлы остаются на устройстве: в демо-версии фото и видео не отправляются диспетчеру.',
          style: JardemTheme.text(11, FontWeight.w500, color: JardemColors.muted, height: 1.3),
        ),
      ],
    ],
  );
}
