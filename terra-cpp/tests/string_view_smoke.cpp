#include <cassert>
#include <string>
#include <string_view>

#include "terra.hpp"

int main() {
    assert(!terra::SpanContext{}.is_valid());
    assert((!(terra::SpanContext{1, 0, 0}).is_valid()));
    assert((!(terra::SpanContext{0, 0, 1}).is_valid()));
    assert(((terra::SpanContext{1, 0, 1}).is_valid()));

    std::string source = "prefix:value:suffix";
    std::string_view view(source.data() + 7, 5);
    std::string buffer;

    const char* z = terra::detail::ensure_z(view, buffer);

    assert(buffer == "value");
    assert(std::string(z) == "value");
    return 0;
}
