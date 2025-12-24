const { validateCustomer } = require('./index');

test('valid customer data', () => {
    const customer = { name: 'John Doe', email: 'john@example.com' };
    expect(validateCustomer(customer)).toBe(true);
});

test('invalid customer data - missing name', () => {
    const customer = { email: 'john@example.com' };
    expect(validateCustomer(customer)).toBe(false);
});

test('invalid customer data - invalid email', () => {
    const customer = { name: 'John Doe', email: 'invalid-email' };
    expect(validateCustomer(customer)).toBe(false);
});