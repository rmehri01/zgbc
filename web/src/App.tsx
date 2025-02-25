import { useEffect } from "react";
import "./App.css";
import init from "../../zig-out/bin/zgbc.wasm?init";
import LoadROMButton from "./LoadROMButton";
import Display from "./Display";

function App() {
  useEffect(() => {
    async function run() {
      const instance = await init();
      console.log(instance.exports);
    }

    void run();
  }, []);

  return (
    <>
      <nav>
        <LoadROMButton />
      </nav>
      <Display />
    </>
  );
}

export default App;
