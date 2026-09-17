from app import calculate_shipping


def test_light_package():
    assert calculate_shipping(3) == 50


def test_medium_package():
    assert calculate_shipping(7) == 100


def test_heavy_package():
    assert calculate_shipping(15) == 150

def test_express_light_package():
    assert calculate_shipping(3, express=True) == 125


def test_express_medium_package():
    assert calculate_shipping(7, express=True) == 175


def test_express_heavy_package():
    assert calculate_shipping(15, express=True) == 225