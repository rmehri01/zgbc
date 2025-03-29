import "./App.css";
import Display from "./Display";
import { Button, useZgbc } from "./wasm";
import { useSetupInputs } from "./inputs";
import { KeybindingRow } from "./KeybindingRow";
import { useSetupAudio } from "./audio";
import { useEffect, useRef, useState } from "react";
import { useSetupSaving } from "./saving";
import Modal from "react-modal";

declare global {
  interface Document {
    webkitExitFullscreen?(): Promise<void>;
  }
  interface Element {
    webkitRequestFullscreen?(): Promise<void>;
  }
}

function App() {
  const [width, setWidth] = useState<number>(window.innerWidth);

  const handleWindowSizeChange = () => {
    setWidth(window.innerWidth);
  };
  useEffect(() => {
    window.addEventListener("resize", handleWindowSizeChange);
    return () => {
      window.removeEventListener("resize", handleWindowSizeChange);
    };
  }, []);

  const isMobile = width <= 1024;

  const gamepad = useRef<Gamepad | null>(null);
  const zgbc = useZgbc(gamepad);

  const { checkGamepadInputs } = useSetupInputs(zgbc, gamepad, isMobile);
  const { updateAudio } = useSetupAudio(zgbc);
  useSetupSaving(zgbc);

  const [modalIsOpen, setIsOpen] = useState(false);

  function openModal(e: React.MouseEvent<HTMLButtonElement, MouseEvent>) {
    setIsOpen(true);
    e.currentTarget.blur();
  }

  function closeModal() {
    setIsOpen(false);
  }

  return (
    <div className="display-container">
      <Display
        zgbc={zgbc}
        checkGamepadInputs={checkGamepadInputs}
        updateAudio={updateAudio}
      />

      {isMobile ? (
        <>
          <div className="tm-text-container">
            <a
              className="tm-text"
              href="https://github.com/rmehri01/zgbc"
              target="_blank"
              rel="noreferrer"
            >
              zgbc
            </a>
          </div>

          <div className="button-container">
            <div className="left-button-container">
              <div className="set" draggable="false">
                <div className="d-pad" draggable="false">
                  <a className="up" draggable="false" />
                  <a className="right" draggable="false" />
                  <a className="down" draggable="false" />
                  <a className="left" draggable="false" />
                </div>
              </div>

              <a className="select">
                <p className="select-text slanted-text">SELECT</p>
              </a>
            </div>

            <div className="right-button-container">
              <div className="ab-container">
                <a className="a">
                  <p className="slanted-text">A</p>
                </a>
                <a className="b">
                  <p className="slanted-text">B</p>
                </a>
              </div>

              <a className="start">
                <p className="start-text slanted-text">START</p>
              </a>
            </div>
          </div>
        </>
      ) : (
        <>
          <div>
            <button className="help" onClick={openModal}>
              Help
            </button>
            <Modal
              isOpen={modalIsOpen}
              onRequestClose={closeModal}
              ariaHideApp={false}
              className="content"
              overlayClassName="overlay"
            >
              <h1>Keybindings</h1>
              <hr />
              <table>
                <tbody>
                  {Object.values(Button)
                    .filter((b) => typeof b === "string")
                    .map((name) => (
                      <KeybindingRow key={name} buttonName={name} />
                    ))}
                </tbody>
              </table>
            </Modal>
          </div>

          <a
            className="tm-text"
            href="https://github.com/rmehri01/zgbc"
            target="_blank"
            rel="noreferrer"
          >
            zgbc
          </a>
        </>
      )}
    </div>
  );
}

export default App;
