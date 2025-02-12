defmodule Membrane.WAV.SerializerTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, RawAudio}
  alias Membrane.Testing.Pipeline

  @module Membrane.WAV.Serializer

  @input_path Path.expand("fixtures/input.wav", __DIR__)
  @reference_path Path.expand("fixtures/reference.wav", __DIR__)
  @processed_path Path.expand("fixtures/reference_processed.wav", __DIR__)

  describe "Serializer should" do
    test "create header properly for one channel" do
      format = %RawAudio{
        channels: 1,
        sample_rate: 16_000,
        sample_format: :s16le
      }

      reference_header = <<
        "RIFF",
        0::32,
        "WAVE",
        "fmt ",
        16::32-little,
        1::16-little,
        1::16-little,
        16_000::32-little,
        32_000::32-little,
        2::16-little,
        16::16-little,
        "data",
        0::32-little
      >>

      {actions, _state} = @module.handle_stream_format(:input, format, %{}, %{header_length: 0})

      assert [
               stream_format: _stream_format,
               buffer: {:output, %Buffer{payload: ^reference_header}}
             ] = actions
    end

    test "create header properly for two channels" do
      format = %RawAudio{
        channels: 2,
        sample_rate: 44_100,
        sample_format: :s24le
      }

      reference_header = <<
        "RIFF",
        0::32,
        "WAVE",
        "fmt ",
        16::32-little,
        1::16-little,
        2::16-little,
        44_100::32-little,
        264_600::32-little,
        6::16-little,
        24::16-little,
        "data",
        0::32-little
      >>

      {actions, _state} = @module.handle_stream_format(:input, format, %{}, %{header_length: 0})

      assert [
               stream_format: _stream_format,
               buffer: {:output, %Buffer{payload: ^reference_header}}
             ] = actions
    end

    test "work when seeking is disabled" do
      {:ok, <<header::44-bytes, payload::8-bytes>>} = File.read(@reference_path)

      structure = [
        child(:file_src, %Membrane.File.Source{location: @input_path})
        |> child(:parser, Membrane.WAV.Parser)
        |> child(:serializer, %@module{disable_seeking: true})
        |> child(:sink, Membrane.Testing.Sink)
      ]

      {:ok, _supervisor_pid, pid} = Pipeline.start_link(structure: structure)

      assert_sink_buffer(pid, :sink, %Buffer{payload: ^header})
      assert_sink_buffer(pid, :sink, %Buffer{payload: ^payload})
      refute_sink_event(pid, :sink, %Membrane.File.SeekSinkEvent{})
      assert_end_of_stream(pid, :sink)

      Pipeline.terminate(pid, blocking?: true)
    end

    @tag :tmp_dir
    test "create valid file when seeking is enabled", %{tmp_dir: tmp_dir} do
      output_path = Path.join([tmp_dir, "output.wav"])

      structure = [
        child(:file_src, %Membrane.File.Source{location: @input_path})
        |> child(:parser, Membrane.WAV.Parser)
        |> child(:serializer, %@module{disable_seeking: false})
        |> child(:file_sink, %Membrane.File.Sink{location: output_path})
      ]

      {:ok, _supervisor_pid, pid} = Pipeline.start_link(structure: structure)

      assert_end_of_stream(pid, :file_sink)
      assert :ok == Pipeline.terminate(pid, blocking?: true)

      {:ok, output} = File.read(output_path)
      {:ok, reference} = File.read(@processed_path)

      assert output == reference
    end
  end
end
