from proptest import VERSION
from std.testing import assert_equal, TestSuite


def test_package_version() raises:
    assert_equal(VERSION, "0.1.0")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
