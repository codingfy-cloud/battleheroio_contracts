// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./node_modules/@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./node_modules/@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "./node_modules/@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "./node_modules/@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./node_modules/@openzeppelin/contracts/utils/Context.sol";
import "./node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "./node_modules/@openzeppelin/contracts/utils/Strings.sol";
import "./shared/BattleHeroData.sol";


/**
 * @dev {ERC721} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *  - token ID and URI autogeneration
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 */



contract BattleHeroFactory is
    Context,
    AccessControlEnumerable,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Pausable
{
    struct Hero{
        address owner;
        string genetic;
        uint bornAt;
        uint256 index;
        bool exists;
        BattleHeroData.DeconstructedGen deconstructed;
    }

    struct Filter{
        bool byRarity;
        BattleHeroData.Rare rarity;
        bool byAsset;
        BattleHeroData.Asset asset;        
    }

    using Counters for Counters.Counter;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");    
    bytes32 public constant LOCKER_ROLE = keccak256("LOCKER_ROLE");    

    address breedAdmin;
    
    Counters.Counter private _tokenIdTracker;

    string private _baseTokenURI = "https://batlehero.io/token/";
    mapping(address => mapping(uint256 => Hero)) _heroes;
    mapping(uint256 => Hero) _allHeroes;
    uint256[] _heroesId;    
    mapping(uint256 => Hero) lockedHeroes;

    uint256 createdAt;
    address owner;

    BattleHeroData _bData;


    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     *
     * Token URIs will be autogenerated based on `baseURI` and their token IDs.
     * See {ERC721-tokenURI}.
     */
    constructor(address bData) ERC721("Heroes And Weapons", "HAW") {                
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(LOCKER_ROLE, _msgSender());
        breedAdmin = msg.sender;
        createdAt = block.timestamp;
        owner = msg.sender;
        _bData = BattleHeroData(bData);
    }
    modifier isSetup() {
        require(address(_bData) != address(0), "Setup is not correct");        
        _;
    }
    function setMinterRole(address minter) public{
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Invalid role admin");
        _setupRole(MINTER_ROLE, minter);        
    }
    function setLockerRole(address locker) public{
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Invalid role admin");
        _setupRole(LOCKER_ROLE, locker);        
    }


    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function lockHero(uint256 tokenId) public{
        require(hasRole(LOCKER_ROLE, msg.sender), "You are not locker");
        lockedHeroes[tokenId] = heroeOfId(tokenId);
    }

    function unlockHero(uint256 tokenId) public {
        require(hasRole(LOCKER_ROLE, msg.sender), "You are not locker");
        delete lockedHeroes[tokenId];
    }
    function isLocked(uint256 tokenId) public view returns(bool) {
        return lockedHeroes[tokenId].exists == true;
    }
   
    /**
     * @dev Creates a new token for `to`. Its token ID will be automatically
     * assigned (and available on the emitted {IERC721-Transfer} event), and the token
     * URI autogenerated based on the base URI passed at construction.
     *
     * See {ERC721-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, string memory genes) public virtual whenNotPaused isSetup returns(uint){ 
        uint tokenId = _tokenIdTracker.current(); 
        require(hasRole(MINTER_ROLE, _msgSender()), "Invalid role");        
        // We cannot just use balanceOf to create the new tokenId because tokens
        // can be burned (destroyed), so we need a separate counter.
        _mint(to, tokenId);
        Hero memory hero = Hero(to, genes, block.timestamp, tokenId, true, _bData.deconstructGen(genes));
        _heroes[to][tokenId] = hero;  
        _allHeroes[tokenId] = hero;
        _heroesId.push(tokenId);
        _tokenIdTracker.increment();
        return tokenId;
    }
    function heroeOfId(uint256 tokenId) public view returns(Hero memory) { 
        return _allHeroes[tokenId];
    }
    function heroesId() public view returns(uint256[] memory){
        return _heroesId;
    }
    function heroesOfOwner(address from, uint page, Filter memory filter) public view returns(Hero[] memory) {   
        uint results_per_page = 20;
        uint greeter_than = results_per_page * page;
        uint start_pointer = (results_per_page * page) - results_per_page;
        uint heroes_length = _heroesId.length;
        uint counter = 0;
        uint index = start_pointer;
        Hero[] memory h = new Hero[](results_per_page);
        if(heroes_length == 0){
            return h;
        }
        
        for(uint i = start_pointer; i < greeter_than; i++){
            if(i <= heroes_length - 1){
                uint256 _tokenId  = _heroesId[index];    
                index = index + 1;                
                Hero memory _h    = heroeOfId(_tokenId);
                if(filter.byRarity == true){
                    BattleHeroData.Rare rare = _bData.getRarity(_h.deconstructed._rarity).rare;
                    if(rare != filter.rarity){
                        continue;
                    }
                }
                if(filter.byAsset == true){
                    BattleHeroData.Asset asset = _bData.getAssetType(_h.deconstructed._type).asset;
                    if(asset != filter.asset){
                        continue;
                    }
                }
                if(_h.owner != from){
                    continue;
                }
                h[counter]        = _h;
                counter = counter + 1;
            }
        }
        return h;
    }
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId)) : "";
    }
    function isApproved(address to, uint256 tokenId) public view returns (bool){
        return _isApprovedOrOwner(to, tokenId);
    }
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        transferTo(from, to, tokenId);
    }
    function transferTo(
        address from,
        address to,
        uint256 tokenId) internal{
        require(!lockedHeroes[tokenId].exists , "Hero can not be transferred because it is locked");
        _transferHero(tokenId, from, to);
        _safeTransfer(from, to, tokenId, "");
    }
    function _transferHero(uint256 tokenId,address from, address to) internal{
        require(_allHeroes[tokenId].deconstructed._transferible < 50, "This hero is not transferible");
        Hero memory h        = _allHeroes[tokenId];        
        Hero memory newHero  = Hero(to, h.genetic, h.bornAt, h.index, h.exists, h.deconstructed);        
        _allHeroes[tokenId]  = newHero;
        _heroes[to][tokenId] = newHero;                
        delete _heroes[from][tokenId];      
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC721Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have pauser role to pause");
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC721Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have pauser role to unpause");
        _unpause();
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable, ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
