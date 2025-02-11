import { useEffect, useState } from "react";
import "./App.css";
import init from "../../zig-out/bin/zgbc.wasm?init";

function App() {
  const [count, setCount] = useState(0);

  useEffect(() => {
    async function run() {
      const instance = await init();
      console.log(instance.exports);
    }

    void run();
  }, []);

  return (
    <>
      <h1>Vite + React</h1>
      <div className="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
        <p>
          Edit <code>src/App.tsx</code> and save to test HMR
        </p>
      </div>
      <p className="read-the-docs">
        Click on the Vite and React logos to learn more
      </p>
    </>
  );
}

export default App;
