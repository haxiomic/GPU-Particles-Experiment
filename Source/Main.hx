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
	//Buffers
	var textureQuad:GLBuffer;
	var particleUVs:GLBuffer;
	//Render Targets
	var particleData:RenderTarget2Phase;
	//Shaders
	var inititalConditionsShader:InitialConditions;
	var stepParticlesShader:StepParticles;
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

		//we'll need floating point textures
		#if js //load floating point extension
		gl.getExtension('OES_texture_float');
		#end
		#if !js
		gl.enable(gl.VERTEX_PROGRAM_POINT_SIZE);//enable gl_PointSize (auto enabled in webgl)
		#end

		gl.clearColor(0,0,0,1);

		//quad for writing to textures
		textureQuad = gltoolbox.GeometryTools.createQuad(gl, 0, 0, 1, 1);

		//setup particle data
		var dataWidth:Int = 1024;
		var dataHeight:Int = dataWidth;

		//create particle data texture
		particleData = new RenderTarget2Phase(gl, gltoolbox.TextureTools.FloatTextureFactoryRGBA, dataWidth, dataHeight);

		//create particle vertex buffers
		var arrayUVs = new Array<Float>();
		for(i in 0...dataWidth){
			for(j in 0...dataHeight){
				arrayUVs.push(i/dataWidth);
				arrayUVs.push(j/dataHeight);
			}
		}

		particleUVs = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, particleUVs);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(arrayUVs), gl.STATIC_DRAW);
		gl.bindBuffer(gl.ARRAY_BUFFER, null);

		//create shaders
		inititalConditionsShader = new InitialConditions();
		stepParticlesShader = new StepParticles();
		renderParticlesShader = new RenderParticles();

		//write initial data
		reset();
	}

	function reset(){
		inititalConditionsShader.scale.data = 1;
		renderShader(inititalConditionsShader, particleData);
	} 

	override function render (context:RenderContext):Void {
		stepParticles();
		renderParticlesToScreen();
	}

	inline function stepParticles(){
		//set position and velocity uniforms
		stepParticlesShader.isMouseDown.data = isMouseDown;
		stepParticlesShader.multiplier.data = isAltDown == true ? 1 : -1;
		stepParticlesShader.mouse.data.x = (mouse.x/window.width)*2 - 1;//convert to clipspace coordinates
		stepParticlesShader.mouse.data.y = ((window.height-mouse.y)/window.height)*2 - 1;//convert to clipspace coordinates
		stepParticlesShader.particleData.data = particleData.readFromTexture;
		renderShader(stepParticlesShader, particleData);
	}

	inline function renderShader(shader:ShaderBase, target:RenderTarget2Phase, clear:Bool = true){
		gl.viewport(0, 0, target.width, target.height);
		gl.bindFramebuffer(gl.FRAMEBUFFER, target.writeFrameBufferObject);

		if(clear) gl.clear(gl.COLOR_BUFFER_BIT);

		gl.bindBuffer(gl.ARRAY_BUFFER, textureQuad);

		shader.activate(true, true);
		gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
		shader.deactivate();

		target.swap();
	}

	inline function renderParticlesToScreen():Void{
		gl.viewport(0, 0, window.width, window.height);
		gl.bindFramebuffer(gl.FRAMEBUFFER, screenBuffer);

		gl.clear(gl.COLOR_BUFFER_BIT);

		//set vertices
		gl.bindBuffer(gl.ARRAY_BUFFER, particleUVs);

		//set uniforms
		renderParticlesShader.particleData.data = particleData.readFromTexture;

		//draw points
		renderParticlesShader.activate(true, true);
		gl.enable(gl.BLEND);
		gl.blendFunc( gl.SRC_ALPHA, gl.SRC_ALPHA );
		gl.blendEquation(gl.FUNC_ADD);
		gl.drawArrays(gl.POINTS, 0, particleData.width*particleData.height);
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


@:vert('#pragma include("Source/shaders/glsl/no-transform.vert")')
@:frag('
	uniform float scale;
	varying vec2 texelCoord;

	void main(void){
		float r1 = (texelCoord.x)*2.-1.;
		float r2 = (texelCoord.y)*2.-1.;
		gl_FragColor = vec4(vec2(r1, r2)*scale, vec2(r1, r2)*0.000);
	}
')
class InitialConditions extends ShaderBase{}


@:vert('#pragma include("Source/shaders/glsl/no-transform.vert")')
@:frag('
	uniform bool isMouseDown;
	uniform vec2 mouse;
	uniform float multiplier;
	uniform sampler2D particleData;
	varying vec2 texelCoord;

	void main(void){
		vec2 p = texture2D(particleData, texelCoord).rg;
		vec2 v = texture2D(particleData, texelCoord).ba;
		//v+=vec2(0, 0.0001);

		//attract mouse
		if(isMouseDown){
			float g = 0.00001*multiplier;
			float softening = 0.001;
			vec2 r = mouse - p;
			float f = (g/(dot(r,r)+softening));
			vec2 a = normalize(r)*f;
			v+=a;
		}

		float damp = 0.8;
		p+=v;

		//walls
		if(p.x>1.){p.x = 1.; v.x*=-damp;}
		if(p.x<-1.){p.x = -1.; v.x*=-damp;}
		if(p.y>1.){p.y = 1.; v.y*=-damp;}
		if(p.y<-1.){p.y = -1.; v.y*=-damp;}

		v*=0.99;

		gl_FragColor = vec4(p, v);
	}
')
class StepParticles extends ShaderBase{}

@:vert('
	uniform sampler2D particleData;
	attribute vec2 particleUV;//particle texture UV
	varying vec3 color;

	void main(void){
		vec2 p = texture2D(particleData, particleUV).rg;
		vec2 v = texture2D(particleData, particleUV).ba;

		float lv = length(v);
		vec3 cvec = vec3(sin(lv/3.0)*1.5-lv*lv, lv*lv*30.0, lv+lv*lv*10.0);
		color = vec3(0.5, 0.3, 0.13)*0.2+cvec*cvec*800.;

		gl_Position = vec4(p, 0.0, 1.0);
		gl_PointSize = 1.0;
	}
')
@:frag('
	varying vec3 color;

	void main(void){
		gl_FragColor = vec4(color, 1.0);
	}
')
class RenderParticles extends ShaderBase{}


