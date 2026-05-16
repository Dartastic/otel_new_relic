// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

/// Attribute keys for the New Relic → OTel bridge.
///
/// `newrelic.*` keys are package-local — there is no upstream OTel
/// semantic convention for New Relic's mobile-agent event model yet.
/// Stable across the 0.x line.
enum NewRelicBridgeSemantics implements OTelSemantic {
  /// `newrelic.fatal` — boolean flag mirroring `recordError`'s
  /// `isFatal` argument.
  fatal('newrelic.fatal'),

  /// `newrelic.breadcrumb.name` — the breadcrumb name recorded with
  /// `recordBreadcrumb`.
  breadcrumbName('newrelic.breadcrumb.name'),

  /// `newrelic.event.type` — eventType supplied to
  /// `recordCustomEvent`.
  eventType('newrelic.event.type'),

  /// `newrelic.event.name` — optional eventName from
  /// `recordCustomEvent`.
  eventName('newrelic.event.name'),

  /// `newrelic.metric.name` — name supplied to `recordMetric`.
  metricName('newrelic.metric.name'),

  /// `newrelic.metric.category` — category supplied to
  /// `recordMetric`.
  metricCategory('newrelic.metric.category'),

  /// `newrelic.metric.value` — value supplied to `recordMetric`.
  metricValue('newrelic.metric.value'),

  /// `newrelic.metric.count_unit` — `countUnit.label` from
  /// `recordMetric`.
  metricCountUnit('newrelic.metric.count_unit'),

  /// `newrelic.metric.value_unit` — `valueUnit.label` from
  /// `recordMetric`.
  metricValueUnit('newrelic.metric.value_unit'),

  /// `newrelic.interaction.name` — actionName supplied to
  /// `startInteraction`.
  interactionName('newrelic.interaction.name'),

  /// `newrelic.interaction.id` — the interaction ID returned by
  /// `startInteraction` (echoed onto the span for cross-referencing).
  interactionId('newrelic.interaction.id');

  const NewRelicBridgeSemantics(this.key);

  @override
  final String key;

  @override
  String toString() => key;
}
