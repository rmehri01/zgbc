import "./App.css";
import LoadROMButton from "./LoadROMButton";
import Display from "./Display";
import { useZgbc } from "./wasm";
import { useSetupInputs } from "./inputs";

function App() {
  const zgbc = useZgbc();

  const { checkGamepadInputs } = useSetupInputs(zgbc);

  return (
    <>
      <nav>
        <LoadROMButton zgbc={zgbc} />
      </nav>
      <Display zgbc={zgbc} checkGamepadInputs={checkGamepadInputs} />
    </>
  );
}

export default App;
