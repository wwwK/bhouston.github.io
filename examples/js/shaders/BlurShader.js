/**
 * @author bhouston / http://clara.io
 *
 * For a horizontal blur, use X_STEP 1, Y_STEP 0
 * For a vertical blur, use X_STEP 0, Y_STEP 1
 *
 */

THREE.BlurShader = {

	defines: {

		"KERNEL_RADIUS": 4

	},

	uniforms: {

		"tDiffuse":         { type: "t", value: null },
		"size":             { type: "v2", value: new THREE.Vector2( 512, 512 ) },
		"sampleUvOffsets":  { type: "v2v", value: [ new THREE.Vector2( 0, 0 ) ] },
		"sampleWeights":    { type: "1fv", value: [ 1.0 ] },

	},

	vertexShader: [

		"#include <common>",

		"varying vec2 vUv;",

		"void main() {",

			"vUv = uv;",

			"gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );",

		"}"

	].join( "\n" ),

	fragmentShader: [

		"uniform sampler2D tDiffuse;",
		"uniform vec2 size;",

		"uniform vec2 sampleUvOffsets[ KERNEL_RADIUS + 1 ];",
		"uniform float sampleWeights[ KERNEL_RADIUS + 1 ];",

		"varying vec2 vUv;",

		"void main() {",

			"vec2 invSize = 1.0 / size;",

			"float weightSum = sampleWeights[0];",
			"vec4 diffuseSum = texture2D( tDiffuse, vUv ) * weightSum;",

			"for( int i = 1; i <= KERNEL_RADIUS; i ++ ) {",

				"float weight = sampleWeights[i];",
				"vec2 sampleUvOffset = sampleUvOffsets[i] * invSize;",
				"diffuseSum += ( texture2D( tDiffuse, vUv + sampleUvOffset ) + texture2D( tDiffuse, vUv - sampleUvOffset ) ) * weight;",
				"weightSum += 2.0 * weight;",

			"}",

			"gl_FragColor =diffuseSum / weightSum;",

		"}"

	].join( "\n" )

};


THREE.BlurShaderUtils = {

	createSampleWeights: function( kernelRadius, stdDev ) {

		var gaussian = function( x, stdDev ) {
			return Math.exp( - ( x*x ) / ( 2.0 * ( stdDev * stdDev ) ) ) / ( Math.sqrt( 2.0 * Math.PI ) * stdDev );
		};

		var weights = [];

		for( var i = 0; i <= kernelRadius; i ++ ) {
			weights.push( gaussian( i, stdDev ) );
		}

		return weights;
	},

	createSampleOffsets: function( kernelRadius, uvIncrement ) {

		var offsets = [];

		for( var i = 0; i <= kernelRadius; i ++ ) {
			offsets.push( uvIncrement.clone().multiplyScalar( i ) );
		}

		return offsets;

	},

	configure: function( material, kernelRadius, stdDev, uvIncrement ) {

		kernelRadius = kernelRadius | 0;

		if( ( material.defines[ 'KERNEL_RADIUS' ] !== kernelRadius ) || ( material.stdDev != stdDev ) ) {

			material.defines[ 'KERNEL_RADIUS' ] = kernelRadius;
			material.uniforms[ 'sampleUvOffsets' ].value = THREE.BlurShaderUtils.createSampleOffsets( kernelRadius, uvIncrement );
			material.uniforms[ 'sampleWeights' ].value = THREE.BlurShaderUtils.createSampleWeights( kernelRadius, stdDev );

			material.uvIncrement = uvIncrement;
			material.stdDev = stdDev;

			material.needsUpdate = true;
		}

	}

};
