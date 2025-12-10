const buyForm = document.getElementById('buy-form');
const usernameInput = document.getElementById('username');
const useridInput = document.getElementById('userid');
const priceInput = document.getElementById('price');
const buyStatus = document.getElementById('buy-status');

const fetchBtn = document.getElementById('fetch-btn');
const fetchUserIdInput = document.getElementById('fetch-userid');
const fetchStatus = document.getElementById('fetch-status');
const results = document.getElementById('results');

buyForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  buyStatus.textContent = 'Sending...';

  try {
    const payload = {
      username: usernameInput.value.trim(),
      userid: useridInput.value.trim(),
      price: Number(priceInput.value)
    };

    const res = await fetch('/api/buy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Failed to send purchase');

    buyStatus.textContent = `Purchase recorded: $${data.purchase.price}`;
    buyStatus.style.color = '#065f46';
    buyForm.reset();
  } catch (err) {
    buyStatus.textContent = err.message;
    buyStatus.style.color = '#b91c1c';
  }
});

fetchBtn.addEventListener('click', async () => {
  const userid = fetchUserIdInput.value.trim();
  if (!userid) {
    fetchStatus.textContent = 'User ID is required';
    fetchStatus.style.color = '#b91c1c';
    return;
  }

  fetchStatus.textContent = 'Loading...';
  results.innerHTML = '';

  try {
    const res = await fetch(`/api/getAllUserBuys/${userid}`);
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Failed to fetch purchases');

    fetchStatus.textContent = `Found ${data.length} purchases`;
    fetchStatus.style.color = '#0f172a';

    data.forEach((purchase) => {
      const div = document.createElement('div');
      div.className = 'purchase';
      const date = new Date(purchase.timestamp).toLocaleString();
      div.innerHTML = `<strong>${purchase.username}</strong> bought for $${purchase.price} on ${date}`;
      results.appendChild(div);
    });
  } catch (err) {
    fetchStatus.textContent = err.message;
    fetchStatus.style.color = '#b91c1c';
  }
});
