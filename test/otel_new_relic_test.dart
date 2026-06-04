// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newrelic_mobile/loglevel.dart' as nr;
import 'package:newrelic_mobile/metricunit.dart';
import 'package:otel_new_relic/otel_new_relic.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;
  late InMemoryLogExporter logs;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_new_relic-test',
    );
    spans = harness.spans;
    logs = harness.logs;
  });

  setUp(() async {
    await harness.flushLogs();
    harness.clear();
  });

  Map<String, Object> attrsOf(LogRecord r) {
    final out = <String, Object>{};
    final list = r.attributes?.toList() ?? const <Attribute<Object>>[];
    for (final a in list) {
      out[a.key] = a.value;
    }
    return out;
  }

  group('OTelNewrelic.recordError', () {
    test('emits ERROR log with exception.* + newrelic.fatal=false', () async {
      final newrelic = OTelNewrelic(null);
      newrelic.recordError(
        StateError('boom'),
        StackTrace.fromString('frame0'),
        attributes: {'order_id': 42},
      );
      await harness.flushLogs();

      expect(logs.records, hasLength(1));
      final rec = logs.records.single;
      expect(rec.severityNumber, Severity.ERROR);
      expect(rec.body.toString(), contains('boom'));
      final a = attrsOf(rec);
      expect(a['exception.type'], 'StateError');
      expect(a['exception.message'], contains('boom'));
      expect(a['exception.stacktrace'], contains('frame0'));
      expect(a['newrelic.fatal'], false);
      expect(a['order_id'], 42);
    });

    test('emits FATAL log when isFatal=true', () async {
      final newrelic = OTelNewrelic(null);
      newrelic.recordError(
        StateError('boom'),
        null,
        isFatal: true,
      );
      await harness.flushLogs();
      final rec = logs.records.single;
      expect(rec.severityNumber, Severity.FATAL);
      expect(attrsOf(rec)['newrelic.fatal'], true);
    });
  });

  group('OTelNewrelic.recordBreadcrumb', () {
    test('emits INFO log naming the breadcrumb', () async {
      final newrelic = OTelNewrelic(null);
      await newrelic.recordBreadcrumb(
        'checkout-tapped',
        eventAttributes: {'cart_size': 3},
      );
      await harness.flushLogs();

      expect(logs.records, hasLength(1));
      final rec = logs.records.single;
      expect(rec.severityNumber, Severity.INFO);
      expect(rec.body, contains('newrelic.breadcrumb checkout-tapped'));
      final a = attrsOf(rec);
      expect(a['newrelic.breadcrumb.name'], 'checkout-tapped');
      expect(a['cart_size'], 3);
    });
  });

  group('OTelNewrelic.recordCustomEvent', () {
    test('emits INFO log with event.type + event.name', () async {
      final newrelic = OTelNewrelic(null);
      await newrelic.recordCustomEvent(
        'PurchaseFlow',
        eventName: 'step_complete',
        eventAttributes: {'step': 'review'},
      );
      await harness.flushLogs();

      final rec = logs.records.single;
      final a = attrsOf(rec);
      expect(a['newrelic.event.type'], 'PurchaseFlow');
      expect(a['newrelic.event.name'], 'step_complete');
      expect(a['step'], 'review');
    });
  });

  group('OTelNewrelic.recordMetric', () {
    test('emits INFO log with metric.{name,category,value,units}', () async {
      final newrelic = OTelNewrelic(null);
      await newrelic.recordMetric(
        'checkout.duration',
        'commerce',
        value: 1.5,
        countUnit: MetricUnit.OPERATIONS,
        valueUnit: MetricUnit.SECONDS,
      );
      await harness.flushLogs();

      final rec = logs.records.single;
      final a = attrsOf(rec);
      expect(a['newrelic.metric.name'], 'checkout.duration');
      expect(a['newrelic.metric.category'], 'commerce');
      expect(a['newrelic.metric.value'], 1.5);
      expect(a['newrelic.metric.count_unit'], MetricUnit.OPERATIONS.label);
      expect(a['newrelic.metric.value_unit'], MetricUnit.SECONDS.label);
    });
  });

  group('OTelNewrelic.log', () {
    test('maps LogLevel.WARN to Severity.WARN', () async {
      final newrelic = OTelNewrelic(null);
      newrelic.log(nr.LogLevel.WARN, 'slow checkout');
      await harness.flushLogs();
      final rec = logs.records.single;
      expect(rec.severityNumber, Severity.WARN);
      expect(rec.body, 'slow checkout');
    });
  });

  group('OTelNewrelic.startInteraction / endInteraction', () {
    test('opens an INTERNAL span and closes it on endInteraction', () async {
      final newrelic = OTelNewrelic(null);
      final id = await newrelic.startInteraction('CheckoutFlow');
      // null forwarder ⇒ id is '' but the span still exists keyed
      // on the action name.
      expect(id, isEmpty);
      newrelic.endInteraction('CheckoutFlow');

      final span = spans.findSpanByName('newrelic.interaction CheckoutFlow');
      expect(span, isNotNull);
      expect(span!.kind, SpanKind.internal);
      final a = {for (final x in span.attributes.toList()) x.key: x.value};
      expect(a['newrelic.interaction.name'], 'CheckoutFlow');
    });
  });

  group('zone-scoped suppression', () {
    test('suppresses OTel emit', () async {
      final newrelic = OTelNewrelic(null);
      await runWithoutNewRelicBridgeAsync(() async {
        newrelic.recordError(StateError('x'), null);
        await newrelic.recordBreadcrumb('b');
        await newrelic.recordCustomEvent('T');
        await newrelic.recordMetric('m', 'c');
        newrelic.log(nr.LogLevel.INFO, 'hi');
        await newrelic.startInteraction('i');
        newrelic.endInteraction('i');
      });
      await harness.flushLogs();
      expect(logs.records, isEmpty);
      expect(spans.findSpansStartingWith('newrelic.'), isEmpty);
    });
  });
}
