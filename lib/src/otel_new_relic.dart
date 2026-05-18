// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:newrelic_mobile/loglevel.dart' as nr;
import 'package:newrelic_mobile/metricunit.dart';
import 'package:newrelic_mobile/newrelic_mobile.dart';

import 'new_relic_semantics.dart';
import 'otel_new_relic_suppression.dart';

const _loggerName = 'package.newrelic_mobile';
const _tracerName = 'dartastic_otel_libs_new_relic';

/// Bridges New Relic Mobile events into OpenTelemetry.
///
/// New Relic's Flutter SDK is a static singleton with no
/// `beforeSend`-style hook, so this bridge takes the wrapping
/// approach: construct an [OTelNewrelic] around
/// `NewrelicMobile.instance` and call the bridge methods from your
/// code. Each call invokes the underlying New Relic method **and**
/// emits an OTel log record (or span, for interactions) carrying the
/// same payload.
///
/// ```dart
/// // 1. Bring up New Relic as usual.
/// await NewrelicMobile.instance.start(config, () => runApp(MyApp()));
///
/// // 2. Wrap once, near app boot.
/// final nr = OTelNewrelic(NewrelicMobile.instance);
///
/// // 3. Use `nr.recordError`, `nr.recordBreadcrumb`, etc. anywhere
/// //    you would call NewrelicMobile.instance.recordError.
/// nr.recordBreadcrumb('checkout-tapped', {'cart_size': 3});
/// try {
///   // ...business logic...
/// } catch (e, st) {
///   nr.recordError(e, st);
///   rethrow;
/// }
/// ```
///
/// OTel records inherit `trace_id` / `span_id` from `Context.current`,
/// so anything captured inside a `tracer.withSpan` block lands on
/// that span — no double bookkeeping in the backend.
class OTelNewrelic {
  /// Creates a bridge around an existing [NewrelicMobile] instance.
  /// Pass `null` (e.g. in tests, or before New Relic has finished
  /// starting) for an OTel-only sink — methods still emit OTel
  /// records, but the forwarding to New Relic is skipped.
  OTelNewrelic(
    this._newrelic, {
    LoggerProvider? loggerProvider,
    TracerProvider? tracerProvider,
  })  : _loggerProvider = loggerProvider,
        _tracerProvider = tracerProvider;

  final NewrelicMobile? _newrelic;
  final LoggerProvider? _loggerProvider;
  final TracerProvider? _tracerProvider;

  OTelLogger _logger() =>
      (_loggerProvider ?? OTel.loggerProvider()).getLogger(_loggerName);

  Tracer _tracer() =>
      (_tracerProvider ?? OTel.tracerProvider()).getTracer(_tracerName);

  /// Underlying New Relic instance, if one was supplied. Use for any
  /// method the bridge doesn't surface directly.
  NewrelicMobile? get newrelic => _newrelic;

  /// Forwards to `NewrelicMobile.recordError` and emits an OTel
  /// ERROR (or FATAL when [isFatal]) log record carrying
  /// `exception.*` attributes.
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    Map<String, dynamic>? attributes,
    bool isFatal = false,
  }) {
    _newrelic?.recordError(
      error,
      stackTrace,
      attributes: attributes,
      isFatal: isFatal,
    );
    if (newRelicBridgeSuppressed()) return;

    final attrs = <Attribute<Object>>[
      OTel.attributeString('exception.type', error.runtimeType.toString()),
      OTel.attributeString('exception.message', error.toString()),
      if (stackTrace != null)
        OTel.attributeString('exception.stacktrace', stackTrace.toString()),
      OTel.attributeBool(NewRelicBridgeSemantics.fatal.key, isFatal),
    ];
    _addUserAttrs(attrs, attributes);

    _logger().emit(
      severityNumber: isFatal ? Severity.FATAL : Severity.ERROR,
      severityText: isFatal ? 'fatal' : 'error',
      body: error.toString(),
      attributes: OTel.attributes(attrs),
    );
  }

  /// Forwards to `NewrelicMobile.recordBreadcrumb` and emits an OTel
  /// INFO log record naming the breadcrumb.
  Future<void> recordBreadcrumb(
    String name, {
    Map<String, dynamic>? eventAttributes,
  }) async {
    await _newrelic?.recordBreadcrumb(name, eventAttributes: eventAttributes);
    if (newRelicBridgeSuppressed()) return;

    final attrs = <Attribute<Object>>[
      OTel.attributeString(
        NewRelicBridgeSemantics.breadcrumbName.key,
        name,
      ),
    ];
    _addUserAttrs(attrs, eventAttributes);

    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'newrelic.breadcrumb $name',
      attributes: OTel.attributes(attrs),
    );
  }

  /// Forwards to `NewrelicMobile.recordCustomEvent` and emits an OTel
  /// INFO log record carrying `newrelic.event.{type,name}`.
  Future<void> recordCustomEvent(
    String eventType, {
    String eventName = '',
    Map<String, dynamic>? eventAttributes,
  }) async {
    await _newrelic?.recordCustomEvent(
      eventType,
      eventName: eventName,
      eventAttributes: eventAttributes,
    );
    if (newRelicBridgeSuppressed()) return;

    final attrs = <Attribute<Object>>[
      OTel.attributeString(NewRelicBridgeSemantics.eventType.key, eventType),
      if (eventName.isNotEmpty)
        OTel.attributeString(NewRelicBridgeSemantics.eventName.key, eventName),
    ];
    _addUserAttrs(attrs, eventAttributes);

    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: eventName.isEmpty
          ? 'newrelic.event $eventType'
          : 'newrelic.event $eventType $eventName',
      attributes: OTel.attributes(attrs),
    );
  }

  /// Forwards to `NewrelicMobile.recordMetric` and emits an OTel
  /// INFO log record carrying `newrelic.metric.*`. (We emit as a log
  /// rather than an OTel metric to match the bridge's
  /// "every-event-becomes-a-record" model — use the OTel Metrics API
  /// directly when you want pre-aggregated histograms or counters.)
  Future<void> recordMetric(
    String name,
    String category, {
    double? value,
    MetricUnit? countUnit,
    MetricUnit? valueUnit,
  }) async {
    await _newrelic?.recordMetric(
      name,
      category,
      value: value,
      countUnit: countUnit,
      valueUnit: valueUnit,
    );
    if (newRelicBridgeSuppressed()) return;

    final attrs = <Attribute<Object>>[
      OTel.attributeString(NewRelicBridgeSemantics.metricName.key, name),
      OTel.attributeString(
        NewRelicBridgeSemantics.metricCategory.key,
        category,
      ),
      if (value != null)
        OTel.attributeDouble(NewRelicBridgeSemantics.metricValue.key, value),
      if (countUnit != null)
        OTel.attributeString(
          NewRelicBridgeSemantics.metricCountUnit.key,
          countUnit.label,
        ),
      if (valueUnit != null)
        OTel.attributeString(
          NewRelicBridgeSemantics.metricValueUnit.key,
          valueUnit.label,
        ),
    ];

    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'newrelic.metric $category/$name',
      attributes: OTel.attributes(attrs),
    );
  }

  /// Forwards to `NewrelicMobile.log` and emits an OTel log record at
  /// the matching severity.
  void log(nr.LogLevel level, String message) {
    _newrelic?.log(level, message);
    if (newRelicBridgeSuppressed()) return;
    final severity = _toSeverity(level);
    _logger().emit(
      severityNumber: severity,
      severityText: level.name.toLowerCase(),
      body: message,
    );
  }

  /// Forwards to `NewrelicMobile.startInteraction` and opens an
  /// INTERNAL OTel span named `newrelic.interaction <actionName>`.
  /// Returns the New Relic interaction ID (empty string when
  /// interaction tracing is disabled in the agent config).
  ///
  /// The opened span lives until the matching [endInteraction]; the
  /// returned interaction ID is also the key used to retrieve the
  /// span, so the OTel side is keyed identically to New Relic's.
  Future<String> startInteraction(String actionName) async {
    final nrId = (await _newrelic?.startInteraction(actionName)) ?? '';
    if (newRelicBridgeSuppressed()) return nrId;

    final span = _tracer().startSpan(
      'newrelic.interaction $actionName',
      kind: SpanKind.internal,
      attributes: OTel.attributesFromMap({
        NewRelicBridgeSemantics.interactionName.key: actionName,
        if (nrId.isNotEmpty) NewRelicBridgeSemantics.interactionId.key: nrId,
      }),
    );
    // When New Relic returns an empty id (interaction tracing
    // disabled), fall back to the action name so the OTel side
    // still tracks the span.
    final key = nrId.isEmpty ? actionName : nrId;
    _activeInteractions[key] = span;
    return nrId;
  }

  /// Forwards to `NewrelicMobile.endInteraction` and ends the OTel
  /// span opened by the matching [startInteraction].
  void endInteraction(String interactionId) {
    _newrelic?.endInteraction(interactionId);
    if (newRelicBridgeSuppressed()) return;
    final span = _activeInteractions.remove(interactionId);
    span?.end();
  }

  /// Forwards to `NewrelicMobile.setAttribute`. No OTel emission
  /// happens (attributes have no point-in-time event meaning).
  Future<void> setAttribute(String name, dynamic value) async {
    await _newrelic?.setAttribute(name, value);
  }

  /// Forwards to `NewrelicMobile.removeAttribute`.
  Future<void> removeAttribute(String name) async {
    await _newrelic?.removeAttribute(name);
  }

  /// Forwards to `NewrelicMobile.setUserId` and tags the current span
  /// (if any) with `user.id`.
  Future<void> setUserId(String userId) async {
    await _newrelic?.setUserId(userId);
    if (newRelicBridgeSuppressed()) return;
    final span = Context.current.span;
    if (span is Span) {
      span.addAttributes(OTel.attributesFromMap({User.userId.key: userId}));
    }
  }

  final Map<String, Span> _activeInteractions = {};

  void _addUserAttrs(
    List<Attribute<Object>> attrs,
    Map<String, dynamic>? userAttributes,
  ) {
    if (userAttributes == null) return;
    userAttributes.forEach((k, v) {
      if (v == null) return;
      if (v is String) {
        attrs.add(OTel.attributeString(k, v));
      } else if (v is int) {
        attrs.add(OTel.attributeInt(k, v));
      } else if (v is double) {
        attrs.add(OTel.attributeDouble(k, v));
      } else if (v is bool) {
        attrs.add(OTel.attributeBool(k, v));
      } else {
        attrs.add(OTel.attributeString(k, v.toString()));
      }
    });
  }

  Severity _toSeverity(nr.LogLevel level) {
    switch (level) {
      case nr.LogLevel.ERROR:
        return Severity.ERROR;
      case nr.LogLevel.WARN:
        return Severity.WARN;
      case nr.LogLevel.INFO:
        return Severity.INFO;
      case nr.LogLevel.VERBOSE:
        return Severity.TRACE;
      case nr.LogLevel.DEBUG:
        return Severity.DEBUG;
    }
  }
}
