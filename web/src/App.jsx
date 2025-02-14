import { useState, useEffect } from "react";
import "./App.css";
import init from "../../zig-out/bin/zgbc.wasm?init";

function App() {
  const [count, setCount] = useState(0);

  useEffect(() => {
    init().then((instance) => {
      console.log(instance.exports);
    });
  }, []);

  return (
    <>
      <h1>Vite + React</h1>
      <div className="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
        <p>
          Edit <code>src/App.jsx</code> and save to test HMR
        </p>
      </div>
      <p className="read-the-docs">
        Click on the Vite and React logos to learn more
      </p>
    </>
  );
}

export default App;
