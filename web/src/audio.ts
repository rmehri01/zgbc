import { useCallback, useEffect, useRef } from "react";
import { Zgbc } from "./wasm";

const SAMPLE_RATE = 65536;

/** Buffers chunks of audio so that they can be played continuously. */
class SoundBuffer {
  private chunks: Array<AudioBufferSourceNode> = [];
  private isPlaying = false;
  private nextStartTime = 0;

  constructor(
    public context: AudioContext,
    public gainNode: GainNode,
    public bufferSize = 10,
    private debug = false,
  ) {}

  public addChunk(data: AudioChunk) {
    if (this.isPlaying) {
      // if we're already playing, try to just continue playing
      if (this.chunks.length <= this.bufferSize) {
        // schedule & add right now
        this.log("chunk accepted");

        const chunk = this.createChunk(data);
        chunk.start(this.nextStartTime);

        this.nextStartTime += chunk.buffer!.duration;
        this.chunks.push(chunk);
      } else {
        // throw away
        this.log("chunk discarded");
        return;
      }
    } else {
      // if we aren't playing, see if we have enough chunks to start
      if (this.chunks.length < this.bufferSize / 2) {
        // add & don't schedule
        this.log("chunk queued");

        const chunk = this.createChunk(data);
        this.chunks.push(chunk);
      } else {
        // add & schedule entire buffer
        this.log("queued chunks scheduled");

        const chunk = this.createChunk(data);
        this.chunks.push(chunk);
        this.isPlaying = true;
        this.nextStartTime = this.context.currentTime;

        for (const chunk of this.chunks) {
          chunk.start(this.nextStartTime);
          this.nextStartTime += chunk.buffer!.duration;
        }
      }
    }
  }

  private createChunk(chunk: AudioChunk): AudioBufferSourceNode {
    const audioBuffer = this.context.createBuffer(
      2,
      chunk.left.length,
      this.context.sampleRate,
    );
    audioBuffer.getChannelData(0).set(chunk.left);
    audioBuffer.getChannelData(1).set(chunk.right);

    const source = this.context.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(this.gainNode);
    source.onended = () => {
      this.chunks.shift();
      if (this.chunks.length === 0) {
        this.isPlaying = false;
        this.nextStartTime = 0;
      }
    };

    return source;
  }

  private log(msg: string) {
    if (this.debug) {
      console.log(`${new Date().toUTCString()}: ${msg}`);
    }
  }
}

/** A chunk of audio with separate left and right channels of the same length. */
interface AudioChunk {
  left: Float32Array;
  right: Float32Array;
}

export function useSetupAudio(zgbc: Zgbc | null): { updateAudio: () => void } {
  const soundBufferRef = useRef<SoundBuffer | null>(null);

  const initSoundBuffer = () => {
    if (!soundBufferRef.current) {
      const audioContext = new AudioContext({
        sampleRate: SAMPLE_RATE,
        latencyHint: "interactive",
      });

      const gainNode = audioContext.createGain();
      gainNode.gain.setValueAtTime(0.25, audioContext.currentTime);
      gainNode.connect(audioContext.destination);

      soundBufferRef.current = new SoundBuffer(audioContext, gainNode);
    }
  };

  useEffect(() => {
    window.addEventListener("click", initSoundBuffer);

    return () => {
      window.removeEventListener("click", initSoundBuffer);
    };
  }, []);

  const updateAudio = useCallback(() => {
    if (!soundBufferRef.current || !zgbc) return;

    const leftAudioChunk = zgbc.readLeftAudioChannel();
    const rightAudioChunk = zgbc.readRightAudioChannel();
    if (leftAudioChunk.length !== 0) {
      soundBufferRef.current.addChunk({
        left: leftAudioChunk,
        right: rightAudioChunk,
      });
    }
  }, [zgbc]);

  return {
    updateAudio,
  };
}
