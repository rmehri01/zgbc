import "./App.css";
import LoadROMButton from "./LoadROMButton";
import Display from "./Display";
import { useZgbc } from "./wasm";
import { useSetupInputs } from "./inputs";

function App() {
  const zgbc = useZgbc();

  useSetupInputs(zgbc);

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
