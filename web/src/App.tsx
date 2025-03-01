import "./App.css";
import LoadROMButton from "./LoadROMButton";
import Display from "./Display";
import { useZgbc } from "./wasm";

function App() {
  const zgbc = useZgbc();

  return (
    <>
      <nav>
        <LoadROMButton zgbc={zgbc} />
      </nav>
      <Display zgbc={zgbc} />
    </>
  );
}

export default App;
