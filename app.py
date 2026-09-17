def calculate_shipping(weight, express=False):
    if weight <= 5:
        cost = 50
    elif weight <= 10:
        cost = 100
    else:
        cost = 150

    if express:
        cost += 75

    return cost


if __name__ == "__main__":
    print("Shipping Calculator")
    print(calculate_shipping(7))


