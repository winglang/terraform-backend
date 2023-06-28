import nodeFetch from "node-fetch";

export async function fetch(method, url, headers = {}, body = undefined) {
  const response = await nodeFetch(url, {
    method,
    body: body ? JSON.stringify(body) : undefined,
    headers: {
      "Content-Type": "application/json",
      ...headers,
    }
  });

  if (!response.ok || response.status == 204) {
    console.log(`Error fetching ${url}: ${response.status} ${response.statusText}`);
    const body = await response.text();
    console.log({body});
    return {
      status: response.status,
      statusText: response.statusText,
      body
    }
  }

  return {
    status: response.status,
    statusText: response.statusText,
    body: await response.json()
  }
}

export function base64encode(str) {
  return Buffer.from(str, 'utf8').toString('base64');
}
