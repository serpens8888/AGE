package audio

import sdl "vendor:sdl3"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "base:runtime"

Error :: union #shared_nil{
    runtime.Allocator_Error,
    Audio_Error,
}

Audio_Error :: enum{
    NO_ERROR,
    SDL_FAILURE,
}

Oscillator_Proc :: #type proc(f32) -> f32

Oscillator :: struct{
    phase: f32,
    phase_inc: f32,
    procedure: Oscillator_Proc,
    frequency: f32,
    sample_rate: f32,
}

sine_approx :: proc(x: f32) -> f32{
    a: f32 = math.mod(x+1, 2) - 1
    return (4*a) * (1-math.abs(a))
}

sine_oscillator :: proc(freq: f32, sample_rate: f32) -> Oscillator{
    return {
        phase = 0,
        phase_inc = freq/sample_rate,
        procedure = sine_approx,
        frequency = freq,
        sample_rate = sample_rate,
    }
}


saw_fn :: proc(x: f32) -> f32{
    return math.mod(2*x, 2)-1
}

saw_oscillator :: proc(freq: f32, sample_rate: f32) -> Oscillator{
    return {
        phase = 0,
        phase_inc = freq/sample_rate,
        procedure = saw_fn,
        frequency = freq,
        sample_rate = sample_rate,
    }
}

tri_fn :: proc(x: f32) -> f32{
    return 2 * math.abs(math.mod(2*x,2)-1)-1
}

tri_oscillator :: proc(freq: f32, sample_rate: f32) -> Oscillator{
    return {
        phase = 0,
        phase_inc = freq/sample_rate,
        procedure = tri_fn,
        frequency = freq,
        sample_rate = sample_rate,
    }
}

square_fn :: proc(x: f32) -> f32{
        fract := linalg.fract(x)
        if(fract >= 0.5){ return 1}
        return -1
}

square_oscillator :: proc(freq: f32, sample_rate: f32) -> Oscillator{
    return {
        phase = 0,
        phase_inc = freq/sample_rate,
        procedure = square_fn,
        frequency = freq,
        sample_rate = sample_rate,
    }
}


next :: proc(osc: ^Oscillator) -> f32{
    sample := osc.procedure(osc.phase)
    osc.phase += osc.phase_inc
    if(osc.phase > 1){
        osc.phase = 0
    }

    return sample
}

change_freq :: proc(osc: ^Oscillator, new_freq: f32){
    osc.frequency = new_freq
    osc.phase_inc = new_freq/osc.sample_rate
}


@(require_results)
check_sdl_handle :: proc(res: ^$T, loc := #caller_location) -> Error{
    if(res == nil){
        fmt.eprintln(sdl.GetError(), loc)
        return .SDL_FAILURE
    }
    return nil
}

@(require_results)
check_sdl_bool :: proc(res: bool, loc := #caller_location) -> Error{
    if(!res){
        fmt.eprintln(sdl.GetError(), loc)
        return .SDL_FAILURE
    }
    return nil
}

check_sdl :: proc{
    check_sdl_bool,
    check_sdl_handle,
}



@(require_results)
initialize_audio :: proc(channels: i32, sample_rate: i32) -> (device: sdl.AudioDeviceID, stream: ^sdl.AudioStream, err: Error){

    audio_spec: sdl.AudioSpec = {
        format = .F32,
        channels = channels,
        freq = sample_rate,
    }

    stream = sdl.CreateAudioStream(&audio_spec, &audio_spec)
    check_sdl(stream) or_return

    device = sdl.OpenAudioDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, nil)
    check_sdl(stream) or_return

    check_sdl(sdl.BindAudioStream(device, stream)) or_return
    
    return

}














