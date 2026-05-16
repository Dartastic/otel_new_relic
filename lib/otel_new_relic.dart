// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// OpenTelemetry bridge for `package:newrelic_mobile`.
///
/// Wrap `NewrelicMobile.instance` with [OTelNewrelic] and every New
/// Relic event the bridge forwards to NR also lands as an OTel log
/// record (errors, breadcrumbs, custom events, metrics, agent logs)
/// or span (interactions), inheriting `trace_id` / `span_id` from
/// `Context.current`.
library;

export 'src/new_relic_semantics.dart';
export 'src/otel_new_relic.dart';
export 'src/otel_new_relic_suppression.dart';
