'use client'

import { useState } from 'react';

export default function Home() {
  const [url, setUrl] = useState('');
  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    fetch('https://droopy.mechanicalturk.one/api/stealth/scrape', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ urlLink: url }),
    })
      .then(async (res) => {
        // Extract filename from Content-Disposition header
        let filename = 'units.csv'; // Default filename

        // Convert response to blob and return it with the filename
        return res.blob().then(blob => ({ blob, filename }));
      })
      .then(({ blob, filename }) => {
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
      })
      .catch((error) => console.error('Error:', error));
  }

  // Return statement should be here
  return (
    <form onSubmit={handleSubmit}>
      <input
        type="text"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
      />
      <button type="submit">Submit</button>
    </form>
  );
}
