
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract ERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }
    
    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        
        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);
        
        return true;
    }
    
    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[to] += amount;
    }
    
    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[from];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[from] = accountBalance - amount;
        _totalSupply -= amount;
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
    }
}

/**
 * @title Automated Market Machine (AMM)
 * @dev A decentralized exchange implementing constant product formula (x * y = k)
 * @author Your Name
 */
contract AutomatedMarketMachine is ERC20 {
    
    // State variables
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    
    uint256 public reserveA;
    uint256 public reserveB;
    
    uint256 public constant TRADING_FEE = 30; // 0.3% trading fee
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 private constant MINIMUM_LIQUIDITY = 1000;
    
    // Reentrancy guard
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    // Events
    event LiquidityAdded(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event LiquidityRemoved(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event Swap(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    /**
     * @dev Constructor to initialize the AMM with two tokens
     * @param _tokenA Address of the first token
     * @param _tokenB Address of the second token
     */
    constructor(
        address _tokenA,
        address _tokenB
    ) ERC20("AMM-LP-Token", "AMM-LP") {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid token addresses");
        require(_tokenA != _tokenB, "Tokens must be different");
        
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        _status = _NOT_ENTERED;
    }
    
    /**
     * @dev Add liquidity to the pool
     * @param amountA Desired amount of tokenA to add
     * @param amountB Desired amount of tokenB to add
     * @param minAmountA Minimum amount of tokenA to add (slippage protection)
     * @param minAmountB Minimum amount of tokenB to add (slippage protection)
     * @return liquidity Amount of LP tokens minted
     */
    function addLiquidity(
        uint256 amountA,
        uint256 amountB,
        uint256 minAmountA,
        uint256 minAmountB
    ) external nonReentrant returns (uint256 liquidity) {
        require(amountA > 0 && amountB > 0, "Amounts must be greater than 0");
        
        // Calculate optimal amounts
        uint256 optimalAmountA = amountA;
        uint256 optimalAmountB = amountB;
        
        if (reserveA > 0 && reserveB > 0) {
            uint256 amountBOptimal = (amountA * reserveB) / reserveA;
            if (amountBOptimal <= amountB) {
                require(amountBOptimal >= minAmountB, "Insufficient tokenB amount");
                optimalAmountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountB * reserveA) / reserveB;
                require(amountAOptimal <= amountA && amountAOptimal >= minAmountA, "Insufficient tokenA amount");
                optimalAmountA = amountAOptimal;
            }
        }
        
        // Transfer tokens from user
        require(tokenA.transferFrom(msg.sender, address(this), optimalAmountA), "Transfer A failed");
        require(tokenB.transferFrom(msg.sender, address(this), optimalAmountB), "Transfer B failed");
        
        // Calculate liquidity tokens to mint
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = sqrt(optimalAmountA * optimalAmountB);
            require(liquidity > MINIMUM_LIQUIDITY, "Insufficient liquidity");
            _mint(address(0), MINIMUM_LIQUIDITY); // Lock minimum liquidity
            liquidity -= MINIMUM_LIQUIDITY;
        } else {
            liquidity = min(
                (optimalAmountA * _totalSupply) / reserveA,
                (optimalAmountB * _totalSupply) / reserveB
            );
        }
        
        require(liquidity > 0, "Insufficient liquidity minted");
        
        // Update reserves
        reserveA += optimalAmountA;
        reserveB += optimalAmountB;
        
        // Mint LP tokens to user
        _mint(msg.sender, liquidity);
        
        emit LiquidityAdded(msg.sender, optimalAmountA, optimalAmountB, liquidity);
    }
    
    /**
     * @dev Remove liquidity from the pool
     * @param liquidity Amount of LP tokens to burn
     * @param minAmountA Minimum amount of tokenA to receive
     * @param minAmountB Minimum amount of tokenB to receive
     * @return amountA Amount of tokenA returned
     * @return amountB Amount of tokenB returned
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 minAmountA,
        uint256 minAmountB
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "Liquidity must be greater than 0");
        require(balanceOf(msg.sender) >= liquidity, "Insufficient LP tokens");
        
        uint256 _totalSupply = totalSupply();
        
        // Calculate token amounts to return
        amountA = (liquidity * reserveA) / _totalSupply;
        amountB = (liquidity * reserveB) / _totalSupply;
        
        require(amountA >= minAmountA && amountB >= minAmountB, "Insufficient output amounts");
        require(amountA > 0 && amountB > 0, "Insufficient liquidity burned");
        
        // Burn LP tokens
        _burn(msg.sender, liquidity);
        
        // Update reserves
        reserveA -= amountA;
        reserveB -= amountB;
        
        // Transfer tokens to user
        require(tokenA.transfer(msg.sender, amountA), "Transfer A failed");
        require(tokenB.transfer(msg.sender, amountB), "Transfer B failed");
        
        emit LiquidityRemoved(msg.sender, amountA, amountB, liquidity);
    }
    
    /**
     * @dev Swap tokens using the constant product formula
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum amount of output tokens (slippage protection)
     * @return amountOut Amount of output tokens received
     */
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Amount in must be greater than 0");
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");
        
        bool isTokenA = tokenIn == address(tokenA);
        (uint256 reserveIn, uint256 reserveOut) = isTokenA 
            ? (reserveA, reserveB) 
            : (reserveB, reserveA);
            
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        // Calculate output amount with fee
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - TRADING_FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
        
        require(amountOut >= minAmountOut, "Insufficient output amount");
        require(amountOut < reserveOut, "Insufficient liquidity");
        
        // Transfer input tokens from user
        if (isTokenA) {
            require(tokenA.transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
            reserveA += amountIn;
            reserveB -= amountOut;
            require(tokenB.transfer(msg.sender, amountOut), "Transfer failed");
            emit Swap(msg.sender, tokenIn, address(tokenB), amountIn, amountOut);
        } else {
            require(tokenB.transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
            reserveB += amountIn;
            reserveA -= amountOut;
            require(tokenA.transfer(msg.sender, amountOut), "Transfer failed");
            emit Swap(msg.sender, tokenIn, address(tokenA), amountIn, amountOut);
        }
    }
    
    /**
     * @dev Get the current reserves of both tokens
     * @return _reserveA Current reserve of tokenA
     * @return _reserveB Current reserve of tokenB
     */
    function getReserves() external view returns (uint256 _reserveA, uint256 _reserveB) {
        return (reserveA, reserveB);
    }
    
    /**
     * @dev Calculate output amount for a given input (without executing the swap)
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @return amountOut Expected amount of output tokens
     */
    function getAmountOut(address tokenIn, uint256 amountIn) 
        external 
        view 
        returns (uint256 amountOut) 
    {
        require(amountIn > 0, "Amount in must be greater than 0");
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid token");
        
        bool isTokenA = tokenIn == address(tokenA);
        (uint256 reserveIn, uint256 reserveOut) = isTokenA 
            ? (reserveA, reserveB) 
            : (reserveB, reserveA);
            
        if (reserveIn == 0 || reserveOut == 0) return 0;
        
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - TRADING_FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }
    
    /**
     * @dev Get token addresses
     * @return tokenAAddr Address of tokenA
     * @return tokenBAddr Address of tokenB
     */
    function getTokens() external view returns (address tokenAAddr, address tokenBAddr) {
        return (address(tokenA), address(tokenB));
    }
    
    // Helper functions
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
    
    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
