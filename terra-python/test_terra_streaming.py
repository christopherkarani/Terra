import unittest

from terra import SpanContext, TerraStreamingSpan


class FakeLib:
    def __init__(self):
        self.calls = []

    def terra_streaming_end(self, span):
        self.calls.append(("streaming_end", span))

    def terra_span_end(self, inst, span):
        self.calls.append(("span_end", inst, span))


class TerraStreamingSpanTests(unittest.TestCase):
    def test_finish_stream_does_not_end_native_span(self):
        lib = FakeLib()
        span = TerraStreamingSpan(lib, 100, 200)

        span.finish_stream()
        span.end()

        self.assertEqual(
            [("streaming_end", 200), ("span_end", 100, 200)],
            lib.calls,
        )

    def test_finish_stream_is_idempotent_before_span_end(self):
        lib = FakeLib()
        span = TerraStreamingSpan(lib, 100, 200)

        span.finish_stream()
        span.finish_stream()
        span.end()

        self.assertEqual(
            [("streaming_end", 200), ("span_end", 100, 200)],
            lib.calls,
        )


class SpanContextTests(unittest.TestCase):
    def test_validity_requires_trace_id_and_span_id(self):
        self.assertFalse(SpanContext().is_valid)
        self.assertFalse(SpanContext(trace_id_hi=1, trace_id_lo=0, span_id=0).is_valid)
        self.assertFalse(SpanContext(trace_id_hi=0, trace_id_lo=0, span_id=1).is_valid)
        self.assertTrue(SpanContext(trace_id_hi=1, trace_id_lo=0, span_id=1).is_valid)

    def test_hex_formatting_is_stable(self):
        context = SpanContext(
            trace_id_hi=0x0123456789ABCDEF,
            trace_id_lo=0x0FEDCBA987654321,
            span_id=0x0011223344556677,
        )

        self.assertEqual("0123456789abcdef0fedcba987654321", context.trace_id_hex)
        self.assertEqual("0011223344556677", context.span_id_hex)


if __name__ == "__main__":
    unittest.main()
