/**
 * @author mrdoob / http://mrdoob.com/
 */

THREE.SpotLightShadow = function () {

	this.cameraNearFar = new THREE.Vector2( 0.5, 500 );
	THREE.LightShadow.call( this, new THREE.PerspectiveCamera( 50, 1, this.cameraNearFar.x, this.cameraNearFar.y ) );

};

THREE.SpotLightShadow.prototype = Object.create( THREE.LightShadow.prototype );
THREE.SpotLightShadow.prototype.constructor = THREE.SpotLightShadow;

THREE.SpotLightShadow.prototype.update = function ( light ) {

	var fov = THREE.Math.RAD2DEG * 2 * light.angle;
	var aspect = this.mapSize.width / this.mapSize.height;
	var far = light.distance || 500;

	var camera = this.camera;

	if ( fov !== camera.fov || aspect !== camera.aspect || far !== camera.far ) {

		this.cameraNearFar.y = far;

		var camera = this.camera;

		camera.fov = fov;
		camera.aspect = aspect;
		camera.far = far;
		camera.updateProjectionMatrix();

	}

};
