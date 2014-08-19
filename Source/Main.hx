package;

import lime.app.Application;
import lime.graphics.GLRenderContext;
import lime.graphics.opengl.GLBuffer;
import lime.graphics.opengl.GLFramebuffer;
import lime.graphics.opengl.GLTexture;
import lime.graphics.RenderContext;
import lime.math.Vector2;
import lime.ui.KeyCode;
import lime.utils.Float32Array;
import gltoolbox.render.RenderTarget2Phase;
import shaderblox.ShaderBase;

class Main extends Application {
	var gl:GLRenderContext;
	var screenBuffer:GLFramebuffer = null;
	var particles:GPUParticles;
	//Shaders
	var mouseForceShader:MouseForceStep;
	var renderParticlesShader:RenderParticles;
	//UI
	var isAltDown:Bool = false;
	var isMouseDown:Bool = false;
	var mouse:Vector2 = new Vector2();

	public function new () {
		super ();			
	}

	public override function init (context:RenderContext):Void {
		this.gl = context.getParameters()[0];
		particles = new GPUParticles(gl);
		renderParticlesShader = new RenderParticles();
		mouseForceShader = new MouseForceStep();
		particles.stepParticlesShader = mouseForceShader;
	}

	function reset(){
		particles.reset();
	} 

	override function render (context:RenderContext):Void {

		mouseForceShader.isMouseDown.data = isMouseDown;
		mouseForceShader.multiplier.data = isAltDown == true ? 1 : -1;
		mouseForceShader.mouse.data.x = (mouse.x/window.width)*2 - 1;//convert to clip space coordinates
		mouseForceShader.mouse.data.y = ((window.height-mouse.y)/window.height)*2 - 1;

		particles.step(1/60);
		renderParticlesToScreen();
	}

	inline function renderParticlesToScreen():Void{
		gl.viewport(0, 0, window.width, window.height);
		gl.bindFramebuffer(gl.FRAMEBUFFER, screenBuffer);

		gl.clearColor(0,0,0,1);
		gl.clear(gl.COLOR_BUFFER_BIT);

		//set vertices
		gl.bindBuffer(gl.ARRAY_BUFFER, particles.particleUVs);

		//set uniforms
		renderParticlesShader.particleData.data = particles.particleData.readFromTexture;

		//draw points
		renderParticlesShader.activate(true, true);
		gl.enable(gl.BLEND);
		gl.blendFunc( gl.SRC_ALPHA, gl.SRC_ALPHA );
		gl.blendEquation(gl.FUNC_ADD);
		gl.drawArrays(gl.POINTS, 0, particles.particleData.width*particles.particleData.height);
		gl.disable(gl.BLEND);
		renderParticlesShader.deactivate();
	}

	override function onMouseDown( x : Float , y : Float , button : Int ) this.isMouseDown = true;

	override function onMouseUp( x : Float , y : Float , button : Int ) this.isMouseDown = false;

	override function onMouseMove( x : Float , y : Float , button : Int ) mouse.setTo(x, y);

	override function onKeyDown( keyCode : Int , modifier : Int ){
		switch (keyCode) {
			case KeyCode.LEFT_ALT, KeyCode.RIGHT_ALT:
				isAltDown = true;
		}
	}

	override function onKeyUp( keyCode : Int , modifier : Int ){
		switch (keyCode) {
			case KeyCode.LEFT_ALT, KeyCode.RIGHT_ALT:
				isAltDown = false;
			case KeyCode.R:
				reset();
		}
	}
}

@:frag('
	uniform bool isMouseDown;
	uniform float multiplier;
	uniform vec2 mouse;

	void main(){
		//attract mouse
		if(isMouseDown){
			float g = 0.001*multiplier;
			float softening = 0.001;
			vec2 r = mouse - p;
			float f = (g/(dot(r,r)+softening));
			vec2 a = normalize(r)*f;
			v+=a*dt;
		}

		float damp = 0.8;
		p+=v*dt;

		//walls
		if(p.x>1.){p.x = 1.; v.x*=-damp;}
		if(p.x<-1.){p.x = -1.; v.x*=-damp;}
		if(p.y>1.){p.y = 1.; v.y*=-damp;}
		if(p.y<-1.){p.y = -1.; v.y*=-damp;}

		v*=0.99;

		step();
	}
')
class MouseForceStep extends GPUParticles.StepParticles{}

@:vert('
	uniform sampler2D particleData;
	attribute vec2 particleUV;//particle texture UV
	varying vec3 color;

	void main(){
		vec2 p = texture2D(particleData, particleUV).rg;

		//generate color
		vec2 v = texture2D(particleData, particleUV).ba;
		float lv = length(v);
		vec3 cvec = vec3(sin(lv/3.0)*1.5-lv*lv*0.7, lv*lv*30.0, lv+lv*lv*10.0);
		color = vec3(0.5, 0.3, 0.13)*0.3+cvec*cvec*800.;

		gl_Position = vec4(p, 0.0, 1.0);
		gl_PointSize = 1.0;
	}
')
@:frag('
	varying vec3 color;

	void main(){
		gl_FragColor = vec4(color, 1.0);
	}
')
class RenderParticles extends ShaderBase{}





